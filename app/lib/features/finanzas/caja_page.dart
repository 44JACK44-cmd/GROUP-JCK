import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../auth/auth_controller.dart';

/// Caja del día: fondo, ingresos, egresos y balance esperado.
/// Solo ADMIN (RLS lo garantiza).
class CajaPage extends ConsumerStatefulWidget {
  const CajaPage({super.key});

  @override
  ConsumerState<CajaPage> createState() => _CajaPageState();
}

class _CajaPageState extends ConsumerState<CajaPage> {
  Map<String, dynamic>? _caja;
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
      final caja = await _sb
          .from('cajas')
          .select('id, fecha_apertura, fondo_inicial, estado')
          .eq('estado', 'ABIERTA')
          .order('fecha_apertura', ascending: false)
          .limit(1)
          .maybeSingle();

      List<Map<String, dynamic>> movs = [];
      if (caja != null) {
        final data = await _sb
            .from('movimiento_caja')
            .select('id, tipo, origen, monto, descripcion, fecha')
            .eq('caja_id', caja['id'])
            .order('fecha', ascending: false)
            .limit(50);
        movs = List<Map<String, dynamic>>.from(data);
      }
      if (!mounted) return;
      setState(() {
        _caja = caja;
        _movimientos = movs;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _error('No pudimos cargar la caja. Revisa tu conexión.');
    }
  }

  double get _ingresos => _movimientos
      .where((m) => m['tipo'] == 'INGRESO')
      .fold(0.0, (s, m) => s + (m['monto'] as num).toDouble());
  double get _egresos => _movimientos
      .where((m) => m['tipo'] == 'EGRESO')
      .fold(0.0, (s, m) => s + (m['monto'] as num).toDouble());
  double get _esperado =>
      ((_caja?['fondo_inicial'] as num?)?.toDouble() ?? 0) + _ingresos - _egresos;

  Future<void> _abrirCaja() async {
    final ctrl = TextEditingController(text: '0.00');
    final fondo = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abrir caja'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Dinero en caja (S/)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text) ?? 0),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
    if (fondo == null) return;
    try {
      await _sb.from('cajas').insert({
        'empresa_id': ref.read(authProvider).empresaId,
        'fondo_inicial': fondo,
      });
      _cargar();
    } catch (_) {
      _error('No se pudo abrir la caja.');
    }
  }

  Future<void> _movimientoManual({required bool esIngreso}) async {
    if (_caja == null) return;
    final montoCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esIngreso ? 'Registrar ingreso' : 'Registrar gasto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto (S/)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final monto = double.tryParse(montoCtrl.text) ?? 0;
    if (monto <= 0) {
      _error('El monto debe ser mayor a cero.');
      return;
    }
    try {
      if (esIngreso) {
        await _sb.from('movimiento_caja').insert({
          'empresa_id': ref.read(authProvider).empresaId,
          'caja_id': _caja!['id'],
          'tipo': 'INGRESO',
          'origen': 'MANUAL',
          'monto': monto,
          'descripcion': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          'usuario_id': ref.read(authProvider).usuarioId,
        });
      } else {
        // El gasto también descuenta de caja
        final mov = await _sb.from('movimiento_caja').insert({
          'empresa_id': ref.read(authProvider).empresaId,
          'caja_id': _caja!['id'],
          'tipo': 'EGRESO',
          'origen': 'GASTO',
          'monto': monto,
          'descripcion': descCtrl.text.trim().isEmpty ? 'Gasto' : descCtrl.text.trim(),
          'usuario_id': ref.read(authProvider).usuarioId,
        }).select('id').single();
        await _sb.from('gastos').insert({
          'empresa_id': ref.read(authProvider).empresaId,
          'descripcion': descCtrl.text.trim().isEmpty ? 'Gasto' : descCtrl.text.trim(),
          'monto': monto,
          'categoria': 'GENERAL',
          'usuario_id': ref.read(authProvider).usuarioId,
          'movimiento_caja_id': mov['id'],
        });
      }
      _cargar();
    } catch (_) {
      _error('No se pudo registrar el movimiento.');
    }
  }

  Future<void> _cerrarCaja() async {
    final ctrl = TextEditingController(text: _esperado.toStringAsFixed(2));
    final declarado = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar caja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Según el sistema deberías tener S/ ${_esperado.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Dinero contado (S/)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text)),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (declarado == null) return;
    try {
      await _sb.from('cajas').update({
        'estado': 'CERRADA',
        'fecha_cierre': DateTime.now().toIso8601String(),
        'monto_declarado': declarado,
      }).eq('id', _caja!['id']);
      _cargar();
    } catch (_) {
      _error('No se pudo cerrar la caja.');
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _labelOrigen(String o) => switch (o) {
        'MANUAL' => 'Manual',
        'GASTO' => 'Gasto',
        'COMBUSTIBLE' => 'Combustible',
        'PAGO' => 'Cobro',
        _ => o,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Caja')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _caja == null
              ? _CajaCerrada(onAbrir: _abrirCaja)
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Resumen
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _FilaResumen('Fondo inicial',
                                  'S/ ${((_caja!['fondo_inicial'] as num?)?.toStringAsFixed(2) ?? '0.00')}'),
                              _FilaResumen('Ingresos', 'S/ ${_ingresos.toStringAsFixed(2)}',
                                  color: AppTheme.success),
                              _FilaResumen('Egresos', 'S/ ${_egresos.toStringAsFixed(2)}',
                                  color: AppTheme.danger),
                              const Divider(height: 20),
                              _FilaResumen('Debería haber',
                                  'S/ ${_esperado.toStringAsFixed(2)}',
                                  destacado: true),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _movimientoManual(esIngreso: false),
                              icon: const Icon(Icons.remove_circle_outline, color: AppTheme.danger),
                              label: const Text('Gasto'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _movimientoManual(esIngreso: true),
                              icon: const Icon(Icons.add_circle_outline, color: AppTheme.success),
                              label: const Text('Ingreso'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _cerrarCaja,
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Cerrar caja del día'),
                      ),
                      const SizedBox(height: 20),
                      Text('Movimientos', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_movimientos.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Sin movimientos todavía.',
                                style: TextStyle(color: Colors.black54)),
                          ),
                        )
                      else
                        for (final m in _movimientos)
                          Card(
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                m['tipo'] == 'INGRESO'
                                    ? Icons.south_west
                                    : Icons.north_east,
                                color: m['tipo'] == 'INGRESO'
                                    ? AppTheme.success
                                    : AppTheme.danger,
                              ),
                              title: Text(m['descripcion'] as String? ??
                                  _labelOrigen(m['origen'] as String? ?? '')),
                              subtitle: Text(_labelOrigen(m['origen'] as String? ?? '')),
                              trailing: Text(
                                '${m['tipo'] == 'INGRESO' ? '+' : '-'}S/ ${(m['monto'] as num).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: m['tipo'] == 'INGRESO'
                                      ? AppTheme.success
                                      : AppTheme.danger,
                                ),
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

class _FilaResumen extends StatelessWidget {
  final String label;
  final String valor;
  final Color? color;
  final bool destacado;

  const _FilaResumen(this.label, this.valor, {this.color, this.destacado = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
              color: destacado ? Colors.black : Colors.black54,
              fontWeight: destacado ? FontWeight.bold : FontWeight.normal)),
          Text(valor, style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: destacado ? 20 : 15,
              color: color ?? (destacado ? AppTheme.primary : Colors.black87))),
        ],
      ),
    );
  }
}

class _CajaCerrada extends StatelessWidget {
  final VoidCallback onAbrir;
  const _CajaCerrada({required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.point_of_sale_outlined, size: 56, color: Colors.black26),
        const SizedBox(height: 16),
        const Center(
          child: Text('La caja está cerrada.\nÁbrela para registrar el dinero del día.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54)),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onAbrir,
          icon: const Icon(Icons.lock_open),
          label: const Text('Abrir caja'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: AppTheme.primary,
          ),
        ),
      ],
    );
  }
}
