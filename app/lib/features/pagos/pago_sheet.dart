/// Hoja de registro de pago de una deuda.
///
/// La usan la sección "Deudas" y la ficha del cliente.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Abre la hoja de cobro. Devuelve {monto, metodo} o null si se cancela.
Future<Map<String, dynamic>?> mostrarHojaPago(
  BuildContext context, {
  required String clienteNombre,
  required double suggestedMonto,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PagoSheet(clienteNombre: clienteNombre, suggestedMonto: suggestedMonto),
  );
}

class _PagoSheet extends StatefulWidget {
  final String clienteNombre;
  final double suggestedMonto;

  const _PagoSheet({required this.clienteNombre, required this.suggestedMonto});

  @override
  State<_PagoSheet> createState() => _PagoSheetState();
}

class _PagoSheetState extends State<_PagoSheet> {
  late final TextEditingController _montoCtrl = TextEditingController(
    text: widget.suggestedMonto.toStringAsFixed(2),
  );
  String _metodo = 'EFECTIVO';

  static const _metodos = {
    'EFECTIVO': '💵 Efectivo',
    'YAPE': '📱 Yape',
    'PLIN': '📱 Plin',
    'TRANSFERENCIA': '🏦 Transferencia',
    'OTRO': '💳 Otro',
  };

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final monto = double.tryParse(_montoCtrl.text) ?? 0;
    if (monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto debe ser mayor a cero.')),
      );
      return;
    }
    Navigator.of(context).pop({'monto': monto, 'metodo': _metodo});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cobrar a ${widget.clienteNombre}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(prefixText: 'S/ ', labelText: 'Monto'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _metodos.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _metodo == e.key,
                    selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: _metodo == e.key ? AppTheme.primary : Colors.black87,
                      fontWeight: _metodo == e.key ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => _metodo = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _confirmar,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Registrar pago'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
