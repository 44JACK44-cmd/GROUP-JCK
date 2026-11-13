/// Formulario de entrega.
///
/// Corto y en el orden en que el motorizado necesita la información:
/// cuánto cobró → con qué método → si quedó deuda → si devolvió el balón
/// vacío → observaciones.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/data/entregas_repo.dart';
import '../../core/domain/formato.dart';

/// Abre el formulario de entrega. Devuelve null si el motorizado cancela.
Future<DatosEntrega?> mostrarFormularioEntrega(
  BuildContext context, {
  required double total,
  required int cantidadBalones,
  int cantidadFierros = 0,
}) {
  return showModalBottomSheet<DatosEntrega>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _EntregaSheet(
      total: total,
      cantidadBalones: cantidadBalones,
      cantidadFierros: cantidadFierros,
    ),
  );
}

class _EntregaSheet extends StatefulWidget {
  final double total;
  final int cantidadBalones;
  final int cantidadFierros;

  const _EntregaSheet({
    required this.total,
    required this.cantidadBalones,
    required this.cantidadFierros,
  });

  @override
  State<_EntregaSheet> createState() => _EntregaSheetState();
}

class _EntregaSheetState extends State<_EntregaSheet> {
  late final TextEditingController _montoCtrl = TextEditingController(
    text: widget.total.toStringAsFixed(2),
  );
  final _observacionesCtrl = TextEditingController();

  String _metodo = 'EFECTIVO';
  bool _quedoDebiendo = false;
  EstadoBalonVacio _balonVacio = EstadoBalonVacio.noRecibido;
  EstadoFierro _fierro = EstadoFierro.noAplica;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  double get _cobrado {
    if (_quedoDebiendo) return 0;
    final v = double.tryParse(_montoCtrl.text) ?? 0;
    return v > widget.total ? widget.total : v;
  }

  double get _deuda => (widget.total - _cobrado) > 0.009 ? widget.total - _cobrado : 0;

  void _elegirMetodo(String metodo) {
    setState(() {
      _metodo = metodo;
      if (metodo == 'DEUDA') {
        _quedoDebiendo = true;
        _montoCtrl.text = '0';
      } else {
        _quedoDebiendo = false;
        if (double.tryParse(_montoCtrl.text) == 0 ||
            double.parse(_montoCtrl.text) >= widget.total) {
          _montoCtrl.text = widget.total.toStringAsFixed(2);
        }
      }
    });
  }

  void _confirmar() {
    if (_quedoDebiendo) {
      Navigator.of(context).pop(DatosEntrega(
        montoCobrado: 0,
        metodo: 'DEUDA',
        balonVacio: _balonVacio,
        fierro: _fierro,
        cantidadBalones: widget.cantidadBalones,
        cantidadFierros: widget.cantidadFierros,
        observaciones: _observacionesCtrl.text.trim().isEmpty
            ? null
            : _observacionesCtrl.text.trim(),
      ));
      return;
    }

    final monto = double.tryParse(_montoCtrl.text) ?? 0;
    if (monto < 0) {
      _aviso('El monto no puede ser negativo.');
      return;
    }
    if (monto > widget.total) {
      _aviso('No puedes cobrar más que ${dinero(widget.total)}.');
      return;
    }

    Navigator.of(context).pop(DatosEntrega(
      montoCobrado: monto,
      metodo: _metodo,
      balonVacio: _balonVacio,
      fierro: _fierro,
      cantidadBalones: widget.cantidadBalones,
      cantidadFierros: widget.cantidadFierros,
      observaciones: _observacionesCtrl.text.trim().isEmpty
          ? null
          : _observacionesCtrl.text.trim(),
    ));
  }

  void _aviso(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final parcial = !_quedoDebiendo && _deuda > 0.009;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Entregar pedido',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Cobrar ${dinero(widget.total)}',
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 18),

            // --- Monto cobrado ---
            const Text('¿Cuánto cobraste?', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              enabled: !_quedoDebiendo,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: 'S/ ',
                prefixStyle: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
                hintText: '0.00',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (parcial)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Pagó parcialmente · debe ${dinero(_deuda)}',
                      style: const TextStyle(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // --- Forma de pago ---
            const Text('Forma de pago', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _BotonPago(
                    etiqueta: '💵 Efectivo',
                    seleccionado: !_quedoDebiendo && _metodo == 'EFECTIVO',
                    onTap: () => _elegirMetodo('EFECTIVO'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BotonPago(
                    etiqueta: '📱 Yape',
                    seleccionado: !_quedoDebiendo && _metodo == 'YAPE',
                    onTap: () => _elegirMetodo('YAPE'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _BotonPago(
                    etiqueta: '💳 Otro',
                    seleccionado: !_quedoDebiendo && _metodo == 'OTRO',
                    onTap: () => _elegirMetodo('OTRO'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BotonPago(
                    etiqueta: '🟠 Quedó debiendo',
                    seleccionado: _quedoDebiendo,
                    color: AppTheme.warning,
                    onTap: () => _elegirMetodo('DEUDA'),
                  ),
                ),
              ],
            ),
            if (_quedoDebiendo)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Debe ${dinero(widget.total)}. Se registrará como deuda del cliente.',
                  style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 18),

            // --- Balón vacío ---
            const Text('¿El cliente entregó el balón vacío?',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _BotonPago(
                    etiqueta: 'Sí',
                    seleccionado: _balonVacio == EstadoBalonVacio.recibido,
                    color: AppTheme.success,
                    onTap: () => setState(() => _balonVacio = EstadoBalonVacio.recibido),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BotonPago(
                    etiqueta: 'No',
                    seleccionado: _balonVacio == EstadoBalonVacio.noRecibido,
                    color: AppTheme.warning,
                    onTap: () => setState(() => _balonVacio = EstadoBalonVacio.noRecibido),
                  ),
                ),
              ],
            ),
            if (_balonVacio == EstadoBalonVacio.noRecibido)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Quedará como balón vacío pendiente.',
                  style: const TextStyle(color: AppTheme.warning, fontSize: 12),
                ),
              ),

            // --- Fierro ---
            if (widget.cantidadFierros > 0) ...[
              const SizedBox(height: 16),
              const Text('¿Devolvió el fierro / soporte?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _BotonPago(
                      etiqueta: 'Sí',
                      seleccionado: _fierro == EstadoFierro.devuelto,
                      color: AppTheme.success,
                      onTap: () => setState(() => _fierro = EstadoFierro.devuelto),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BotonPago(
                      etiqueta: 'No',
                      seleccionado: _fierro == EstadoFierro.pendiente,
                      color: AppTheme.warning,
                      onTap: () => setState(() => _fierro = EstadoFierro.pendiente),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // --- Observaciones ---
            TextField(
              controller: _observacionesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observaciones (opcional)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 18),

            FilledButton.icon(
              onPressed: _confirmar,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Finalizar entrega'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppTheme.success,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Botón grande de opción (forma de pago, sí/no).
class _BotonPago extends StatelessWidget {
  final String etiqueta;
  final bool seleccionado;
  final Color color;
  final VoidCallback onTap;

  const _BotonPago({
    required this.etiqueta,
    required this.seleccionado,
    required this.onTap,
    this.color = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: seleccionado ? color.withValues(alpha: 0.14) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: seleccionado ? color : const Color(0xFFDADDD9),
            width: seleccionado ? 1.6 : 1,
          ),
        ),
        child: Text(
          etiqueta,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: seleccionado ? color : Colors.black87,
            fontWeight: seleccionado ? FontWeight.w700 : FontWeight.w500,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
