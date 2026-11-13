/// Registro rápido de gasto por el motorizado.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/sb.dart';
import '../auth/auth_controller.dart';

class RegistroGastoPage extends ConsumerStatefulWidget {
  const RegistroGastoPage({super.key});

  @override
  ConsumerState<RegistroGastoPage> createState() => _RegistroGastoPageState();
}

class _RegistroGastoPageState extends ConsumerState<RegistroGastoPage> {
  final _descripcionCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _observacionCtrl = TextEditingController();

  String _categoria = 'Combustible';
  bool _guardando = false;

  static const _categorias = {
    'Combustible': '⛽',
    'Reparación': '🔧',
    'Mantenimiento': '🛠️',
    'Estacionamiento': '🅿️',
    'Peaje': '🛣️',
    'Otro': '💳',
  };

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _montoCtrl.dispose();
    _observacionCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final descripcion = _descripcionCtrl.text.trim();
    if (descripcion.isEmpty) {
      _error('Escribe una descripción.');
      return;
    }
    final monto = double.tryParse(_montoCtrl.text) ?? 0;
    if (monto <= 0) {
      _error('El monto debe ser mayor a cero.');
      return;
    }

    setState(() => _guardando = true);
    final auth = ref.read(authProvider);
    try {
      await sb.from('gastos').insert({
        'empresa_id': auth.empresaId,
        'descripcion': descripcion,
        'monto': monto,
        'categoria': _categoria,
        'usuario_id': auth.usuarioId,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gasto registrado.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos registrar el gasto: $e')),
      );
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar gasto')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Tipo de gasto', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _categorias.entries)
                ChoiceChip(
                  label: Text('${e.value} ${e.key}'),
                  selected: _categoria == e.key,
                  selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: _categoria == e.key ? AppTheme.primary : Colors.black87,
                    fontWeight: _categoria == e.key ? FontWeight.w600 : FontWeight.normal,
                  ),
                  onSelected: (v) => setState(() => _categoria = v ? e.key : _categoria),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descripcionCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripción *',
              hintText: 'Ej. Combustible moto',
              prefixIcon: Icon(Icons.description_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monto *',
              prefixText: 'S/ ',
              prefixIcon: Icon(Icons.attach_money),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _observacionCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.check),
            label: Text(_guardando ? 'Guardando…' : 'Guardar gasto'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}
