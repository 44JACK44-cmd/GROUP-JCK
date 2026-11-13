import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../auth/auth_controller.dart';

/// Registro de gastos de combustible por vehículo.
class CombustiblePage extends ConsumerStatefulWidget {
  const CombustiblePage({super.key});

  @override
  ConsumerState<CombustiblePage> createState() => _CombustiblePageState();
}

class _CombustiblePageState extends ConsumerState<CombustiblePage> {
  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _vehiculos = [];
  Map<String, dynamic>? _cajaAbierta;
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
        _sb.from('combustible')
            .select('id, fecha, monto, kilometraje, observacion, vehiculos(nombre)')
            .order('fecha', ascending: false)
            .limit(100),
        _sb.from('vehiculos').select('id, nombre, placa').eq('activo', true).order('nombre'),
        _sb.from('cajas').select('id').eq('estado', 'ABIERTA').limit(1).maybeSingle(),
      ]);
      if (!mounted) return;
      setState(() {
        _registros = List<Map<String, dynamic>>.from(resultados[0] as List);
        _vehiculos = List<Map<String, dynamic>>.from(resultados[1] as List);
        _cajaAbierta = resultados[2] as Map<String, dynamic>?;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _error('No pudimos cargar el combustible. Revisa tu conexión.');
    }
  }

  double get _totalMes {
    final ahora = DateTime.now();
    return _registros
        .where((r) {
          final f = DateTime.tryParse(r['fecha'] as String? ?? '');
          return f != null && f.month == ahora.month && f.year == ahora.year;
        })
        .fold(0.0, (s, r) => s + (r['monto'] as num).toDouble());
  }

  Future<void> _agregar() async {
    final datos = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CombustibleSheet(vehiculos: _vehiculos),
    );
    if (datos == null) return;

    try {
      // Si hay caja abierta, registrar también el egreso.
      String? movCajaId;
      if (_cajaAbierta != null) {
        final mov = await _sb.from('movimiento_caja').insert({
          'empresa_id': ref.read(authProvider).empresaId,
          'caja_id': _cajaAbierta!['id'],
          'tipo': 'EGRESO',
          'origen': 'COMBUSTIBLE',
          'monto': datos['monto'],
          'descripcion': 'Combustible${datos['vehiculoNombre'] != null ? ' — ${datos['vehiculoNombre']}' : ''}',
          'usuario_id': ref.read(authProvider).usuarioId,
        }).select('id').single();
        movCajaId = mov['id'] as String;
      }
      await _sb.from('combustible').insert({
        'empresa_id': ref.read(authProvider).empresaId,
        'vehiculo_id': datos['vehiculoId'],
        'monto': datos['monto'],
        'kilometraje': datos['kilometraje'],
        'observacion': datos['observacion'],
        'usuario_id': ref.read(authProvider).usuarioId,
        'movimiento_caja_id': movCajaId,
      });
      _cargar();
    } catch (_) {
      _error('No se pudo registrar. Inténtalo de nuevo.');
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fecha(String? iso) {
    final f = DateTime.tryParse(iso ?? '');
    if (f == null) return '';
    return '${f.day}/${f.month}/${f.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Combustible')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregar,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.local_gas_station_outlined),
        label: const Text('Cargar'),
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
                          const Icon(Icons.local_gas_station_outlined,
                              size: 36, color: AppTheme.info),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Gastado este mes',
                                    style: TextStyle(color: Colors.black54)),
                                Text('S/ ${_totalMes.toStringAsFixed(2)}',
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
                  if (_registros.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Sin registros de combustible.',
                            style: TextStyle(color: Colors.black54)),
                      ),
                    )
                  else
                    for (final r in _registros)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.local_gas_station_outlined,
                              color: AppTheme.info),
                          title: Text(
                            (r['vehiculos'] as Map?)?['nombre'] as String? ?? 'Vehículo',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text([
                            _fecha(r['fecha'] as String?),
                            if (r['kilometraje'] != null) 'Km: ${r['kilometraje']}',
                            if ((r['observacion'] as String? ?? '').isNotEmpty) r['observacion'],
                          ].join('  ·  ')),
                          trailing: Text('S/ ${(r['monto'] as num).toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _CombustibleSheet extends StatefulWidget {
  final List<Map<String, dynamic>> vehiculos;
  const _CombustibleSheet({required this.vehiculos});

  @override
  State<_CombustibleSheet> createState() => _CombustibleSheetState();
}

class _CombustibleSheetState extends State<_CombustibleSheet> {
  String? _vehiculoId;
  final _montoCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();

  @override
  void dispose() {
    _montoCtrl.dispose();
    _kmCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
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
            const Text('Cargar combustible',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _vehiculoId,
              decoration: const InputDecoration(labelText: 'Vehículo (opcional)'),
              items: [
                for (final v in widget.vehiculos)
                  DropdownMenuItem(
                    value: v['id'] as String,
                    child: Text('${v['nombre']}${v['placa'] != null ? ' (${v['placa']})' : ''}'),
                  ),
              ],
              onChanged: (v) => setState(() => _vehiculoId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto (S/) *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _kmCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Kilometraje (opcional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obsCtrl,
              decoration: const InputDecoration(labelText: 'Observación'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final monto = double.tryParse(_montoCtrl.text) ?? 0;
                if (monto <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('El monto debe ser mayor a cero.')),
                  );
                  return;
                }
                final vehiculo = widget.vehiculos
                    .where((v) => v['id'] == _vehiculoId)
                    .firstOrNull;
                Navigator.of(context).pop({
                  'vehiculoId': _vehiculoId,
                  'vehiculoNombre': vehiculo?['nombre'],
                  'monto': monto,
                  'kilometraje': int.tryParse(_kmCtrl.text),
                  'observacion': _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
                });
              },
              child: const Text('Guardar'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
