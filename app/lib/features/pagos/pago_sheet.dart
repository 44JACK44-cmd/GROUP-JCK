/// Hoja de registro de pago de una deuda o cobro suelto.
///
/// Si el cliente paga por Yape se pide SIEMPRE la foto del comprobante como
/// evidencia. Sin foto se permite continuar solo con confirmación explícita.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/ui/comprobante_picker.dart';

/// Devuelve {monto, metodo, fotoPath} o null si se cancela.
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
  String? _fotoPath;

  static const _metodos = {
    'EFECTIVO': 'Efectivo',
    'YAPE': 'Yape',
    'PLIN': 'Plin',
    'TRANSFERENCIA': 'Transferencia',
    'OTRO': 'Otro',
  };

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final monto = double.tryParse(_montoCtrl.text) ?? 0;
    if (monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto debe ser mayor a cero.')),
      );
      return;
    }

    if (_metodo == 'YAPE' && _fotoPath == null) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sin comprobante'),
          content: const Text(
            'El pago fue por Yape pero no tomaste foto. ¿Registrar igual?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Volver a la foto'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continuar sin foto'),
            ),
          ],
        ),
      );
      if (continuar != true) return;
    }

    if (!mounted) return;
    Navigator.of(context).pop({
      'monto': monto,
      'metodo': _metodo,
      'fotoPath': _fotoPath,
    });
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
                    avatar: Icon(
                      e.key == 'YAPE'
                          ? Icons.account_balance_wallet_outlined
                          : Icons.payments_outlined,
                      size: 17,
                    ),
                    label: Text(e.value),
                    selected: _metodo == e.key,
                    selectedColor: AppTheme.primary.withValues(alpha: 0.12),
                    labelStyle: TextStyle(
                      color: _metodo == e.key ? AppTheme.primary : Colors.black87,
                      fontWeight: _metodo == e.key ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => _metodo = e.key),
                  ),
              ],
            ),
            if (_metodo == 'YAPE') ...[
              const SizedBox(height: 18),
              ComprobantePicker(
                fotoPath: _fotoPath,
                onChanged: (v) => setState(() => _fotoPath = v),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _confirmar,
              icon: const Icon(Icons.check_circle_outline),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              label: const Text('Registrar pago'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
