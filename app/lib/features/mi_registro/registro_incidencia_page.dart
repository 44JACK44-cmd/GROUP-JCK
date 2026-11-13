/// Registro rápido de incidencia/falla por el motorizado.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/sb.dart';
import '../auth/auth_controller.dart';

class RegistroIncidenciaPage extends ConsumerStatefulWidget {
  const RegistroIncidenciaPage({super.key});

  @override
  ConsumerState<RegistroIncidenciaPage> createState() => _RegistroIncidenciaPageState();
}

class _RegistroIncidenciaPageState extends ConsumerState<RegistroIncidenciaPage> {
  final _descripcionCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();

  String _tipo = 'FALLA';
  bool _guardando = false;

  static const _tipos = {
    'FALLA': '⚠️ Falla',
    'REPARACION': '🔧 Reparación',
    'MANTENIMIENTO': '🛠️ Mantenimiento',
    'ESTACIONAMIENTO': '🅿️ Estacionamiento',
    'PEAJE': '🛣️ Peaje',
    'OTRO': '📋 Otro',
  };

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final descripcion = _descripcionCtrl.text.trim();
    if (descripcion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe una descripción.')),
      );
      return;
    }
    final monto = double.tryParse(_montoCtrl.text) ?? 0;

    setState(() => _guardando = true);
    final auth = ref.read(authProvider);
    try {
      await sb.from('incidencias').insert({
        'empresa_id': auth.empresaId,
        'usuario_id': auth.usuarioId,
        'tipo': _tipo,
        'descripcion': descripcion,
        'monto': monto,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incidencia registrada.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos registrar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar falla / incidencia')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Tipo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _tipos.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _tipo == e.key,
                  selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: _tipo == e.key ? AppTheme.primary : Colors.black87,
                    fontWeight: _tipo == e.key ? FontWeight.w600 : FontWeight.normal,
                  ),
                  onSelected: (v) => setState(() => _tipo = v ? e.key : _tipo),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descripcionCtrl,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Descripción *',
              hintText: 'Ej. Cambio de llanta trasera',
              prefixIcon: Icon(Icons.description_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monto (si aplica)',
              prefixText: 'S/ ',
              prefixIcon: Icon(Icons.attach_money),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.check),
            label: Text(_guardando ? 'Guardando…' : 'Guardar'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}
