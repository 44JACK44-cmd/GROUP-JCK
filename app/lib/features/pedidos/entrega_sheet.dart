/// Formulario de entrega.
///
/// Corto y en el orden en que el motorizado necesita la información:
/// cuánto cobró → con qué método → si quedó deuda → si devolvió el balón
/// vacío → observaciones.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

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
  String? _fotoPath;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _tomarFoto(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1280,
      );
      if (x == null || !mounted) return;
      setState(() => _fotoPath = x.path);
    } on PlatformException {
      if (mounted) _aviso('No se pudo abrir la cámara.');
    }
  }

  double get _cobrado {
    if (_quedoDebiendo) return 0;
    final v = double.tryParse(_montoCtrl.text) ?? 0;
    return v > widget.total ? widget.total : v;
  }

  double get _deuda => (widget.total - _cobrado) > 0.009 ? widget.total - _cobrado : 0;

  bool get montoCobradoPositivo => (double.tryParse(_montoCtrl.text) ?? 0) > 0;

  void _elegirMetodo(String metodo) {
    setState(() {
      _metodo = metodo;
      if (metodo == 'DEUDA') {
        _quedoDebiendo = true;
        _montoCtrl.text = '0';
      } else {
        _quedoDebiendo = false;
        if (double.tryParse(_montoCtrl.text) == 0 ||
            (double.tryParse(_montoCtrl.text) ?? 0) >= widget.total) {
          _montoCtrl.text = widget.total.toStringAsFixed(2);
        }
      }
    });
  }

  Future<void> _confirmar() async {
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

    // El comprobante de Yape se pide siempre. Si no hay cámara o se olvidó,
    // se permite continuar con aviso explícito (nunca se finge que se guardó).
    if (_metodo == 'YAPE' && monto > 0 && _fotoPath == null) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Sin comprobante'),
          content: Text(
            'Pagó con Yape pero no tomaste foto del comprobante. '
            '¿Quieres continuar así?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Tomar foto'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Continuar sin foto'),
            ),
          ],
        ),
      );
      if (continuar != true) return;
    }

    if (!mounted) return;
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
      comprobanteLocalPath: _fotoPath,
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
                  color: AppColors.textoMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text('Entregar pedido',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('Cobrar ${dinero(widget.total)}',
                style: TextStyle(color: AppColors.textoSecundario)),
            SizedBox(height: 18),

            // --- Monto cobrado ---
            Text('¿Cuánto cobraste?', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            TextField(
              controller: _montoCtrl,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              enabled: !_quedoDebiendo,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: 'S/ ',
                prefixStyle: TextStyle(
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
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Pagó parcialmente · debe ${dinero(_deuda)}',
                      style: TextStyle(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(height: 16),

            // --- Forma de pago ---
            Text('Forma de pago', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _BotonPago(
                    etiqueta: 'Efectivo',
                    seleccionado: !_quedoDebiendo && _metodo == 'EFECTIVO',
                    onTap: () => _elegirMetodo('EFECTIVO'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _BotonPago(
                    etiqueta: 'Yape',
                    seleccionado: !_quedoDebiendo && _metodo == 'YAPE',
                    onTap: () => _elegirMetodo('YAPE'),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _BotonPago(
                    etiqueta: 'Otro',
                    seleccionado: !_quedoDebiendo && _metodo == 'OTRO',
                    onTap: () => _elegirMetodo('OTRO'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _BotonPago(
                    etiqueta: 'Quedó debiendo',
                    seleccionado: _quedoDebiendo,
                    color: AppTheme.warning,
                    onTap: () => _elegirMetodo('DEUDA'),
                  ),
                ),
              ],
            ),
            if (_quedoDebiendo)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Debe ${dinero(widget.total)}. Se registrará como deuda del cliente.',
                  style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600),
                ),
              ),

            // --- Foto del comprobante de Yape ---
            if (!_quedoDebiendo && _metodo == 'YAPE' && montoCobradoPositivo) ...[
              SizedBox(height: 16),
              Text('Foto del comprobante',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              if (_fotoPath != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_fotoPath!),
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _fotoPath = null),
                  icon: Icon(Icons.delete_outline),
                  label: Text('Quitar foto'),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _tomarFoto(ImageSource.camera),
                        icon: Icon(Icons.photo_camera),
                        label: Text('Tomar foto'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: Size.fromHeight(46)),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _tomarFoto(ImageSource.gallery),
                        icon: Icon(Icons.photo_library_outlined),
                        label: Text('Galería'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: Size.fromHeight(46)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            SizedBox(height: 18),

            // --- Balón vacío ---
            Text('¿El cliente entregó el balón vacío?',
                style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
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
                SizedBox(width: 8),
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
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Quedará como balón vacío pendiente.',
                  style: TextStyle(color: AppTheme.warning, fontSize: 12),
                ),
              ),

            // --- Fierro ---
            if (widget.cantidadFierros > 0) ...[
              SizedBox(height: 16),
              Text('¿Devolvió el fierro / soporte?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
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
                  SizedBox(width: 8),
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
            SizedBox(height: 16),

            // --- Observaciones ---
            TextField(
              controller: _observacionesCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Observaciones (opcional)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            SizedBox(height: 18),

            FilledButton.icon(
              onPressed: _confirmar,
              icon: Icon(Icons.check_circle_outline),
              label: Text('Finalizar entrega'),
              style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(52),
                backgroundColor: AppTheme.success,
              ),
            ),
            SizedBox(height: 8),
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
            color: seleccionado ? color : AppColors.borde,
            width: seleccionado ? 1.6 : 1,
          ),
        ),
        child: Text(
          etiqueta,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: seleccionado ? color : AppColors.textoPrincipal,
            fontWeight: seleccionado ? FontWeight.w700 : FontWeight.w500,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}