/// Registro rápido de gasto por el motorizado.
///
/// La foto del comprobante es opcional. Si no hay Internet, la ruta local se
/// conserva en el Outbox y se sube a Storage al sincronizar.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/data/sb.dart';
import '../../core/offline/outbox.dart';
import '../../core/state/bus.dart';
import '../../core/storage/comprobante_service.dart';
import '../auth/auth_controller.dart';

class RegistroGastoPage extends ConsumerStatefulWidget {
  /// Categoría preseleccionada (permite un botón directo de "Llenar combustible").
  final String? categoriaInicial;

  RegistroGastoPage({super.key, this.categoriaInicial});

  @override
  ConsumerState<RegistroGastoPage> createState() => _RegistroGastoPageState();
}

class _RegistroGastoPageState extends ConsumerState<RegistroGastoPage> {
  final _descripcionCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _observacionCtrl = TextEditingController();

  late String _categoria;
  String _medioPago = 'EFECTIVO';
  String? _fotoPath;
  bool _guardando = false;

  static const _medios = ['EFECTIVO', 'YAPE', 'OTRO'];

  static const _categorias = <String, IconData>{
    'Combustible': Icons.local_gas_station_outlined,
    'Reparación': Icons.build_outlined,
    'Mantenimiento': Icons.handyman_outlined,
    'Estacionamiento': Icons.local_parking_outlined,
    'Peaje': Icons.toll_outlined,
    'Otro': Icons.receipt_long_outlined,
  };

  @override
  void initState() {
    super.initState();
    final inicial = widget.categoriaInicial;
    _categoria = inicial != null && _categorias.containsKey(inicial)
        ? inicial
        : 'Combustible';
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _montoCtrl.dispose();
    _observacionCtrl.dispose();
    super.dispose();
  }

  Future<void> _tomarFoto(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1280,
      );
      if (x != null && mounted) setState(() => _fotoPath = x.path);
    } catch (_) {
      if (mounted) _error('No se pudo abrir la cámara.');
    }
  }

  Future<void> _guardar() async {
    final descripcion = _descripcionCtrl.text.trim();
    if (descripcion.isEmpty) {
      _error('Escribe una descripción.');
      return;
    }
    final monto = double.tryParse(_montoCtrl.text.replaceAll(',', '.')) ?? 0;
    if (monto <= 0) {
      _error('El monto debe ser mayor a cero.');
      return;
    }

    final observacion = _observacionCtrl.text.trim();
    final descripcionCompleta = observacion.isEmpty
        ? descripcion
        : '$descripcion — $observacion';

    setState(() => _guardando = true);
    final auth = ref.read(authProvider);
    final uuid = Uuid().v4();
    final datos = <String, dynamic>{
      'empresa_id': auth.empresaId,
      'descripcion': descripcionCompleta,
      'monto': monto,
      'categoria': _categoria,
      'usuario_id': auth.usuarioId,
      'medio_pago': _medioPago,
      'fecha': DateTime.now().toIso8601String(),
      'uuid_offline': uuid,
      if (_fotoPath != null) 'comprobante_local_path': _fotoPath,
    };

    String? comprobanteUrl;
    if (_fotoPath != null) {
      comprobanteUrl = await ComprobanteService.subir(_fotoPath!);
    }
    final fotoPendiente = _fotoPath != null && comprobanteUrl == null;

    if (!fotoPendiente) {
      final fila = Map<String, dynamic>.from(datos)
        ..remove('comprobante_local_path');
      if (comprobanteUrl != null) fila['comprobante_url'] = comprobanteUrl;
      try {
        try {
          await sb.from('gastos').insert(fila);
        } catch (e) {
          if (esErrorDeRed(e)) rethrow;
          if (!esColumnaAusente(e) && !esValorInvalido(e)) rethrow;
          final reintento = Map<String, dynamic>.from(fila)
            ..remove('comprobante_url')
            ..remove('medio_pago')
            ..remove('uuid_offline');
          await sb.from('gastos').insert(reintento);
        }
        SyncBus.dineroCambio();
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gasto registrado.')),
        );
        return;
      } catch (e) {
        if (!esErrorDeRed(e)) {
          if (!mounted) return;
          setState(() => _guardando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                traducirError(e, contexto: 'No pudimos registrar el gasto').mensaje,
              ),
            ),
          );
          return;
        }
        // Sin conexión: se encola con la foto local.
      }
    }

    await Outbox.encolarGasto(
      gasto: datos,
      comprobanteLocalPath: _fotoPath,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Guardado en el dispositivo. Se sincronizará automáticamente.'),
      ),
    );
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Registrar gasto')),
      body: ListView(
        padding: EdgeInsets.all(20),
        children: [
          Text('Tipo de gasto', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _categorias.entries)
                ChoiceChip(
                  avatar: Icon(e.value, size: 18),
                  label: Text(e.key),
                  selected: _categoria == e.key,
                  selectedColor: AppTheme.primary.withValues(alpha: 0.12),
                  labelStyle: TextStyle(
                    color: _categoria == e.key ? AppTheme.primary : AppColors.textoPrincipal,
                    fontWeight: _categoria == e.key ? FontWeight.w600 : FontWeight.normal,
                  ),
                  onSelected: (v) => setState(() => _categoria = v ? e.key : _categoria),
                ),
            ],
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _descripcionCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Descripción *',
              hintText: 'Ej. Combustible moto',
              prefixIcon: Icon(Icons.description_outlined),
            ),
          ),
          SizedBox(height: 12),
          TextFormField(
            controller: _montoCtrl,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monto *',
              prefixText: 'S/ ',
              prefixIcon: Icon(Icons.attach_money),
            ),
          ),
          SizedBox(height: 12),
          Text('¿Con qué se pagó?',
              style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final m in _medios)
                ChoiceChip(
                  label: Text(m == 'EFECTIVO'
                      ? 'Efectivo'
                      : m == 'YAPE'
                          ? 'Yape'
                          : 'Otro'),
                  selected: _medioPago == m,
                  selectedColor: AppTheme.primary.withValues(alpha: 0.12),
                  onSelected: (_) => setState(() => _medioPago = m),
                ),
            ],
          ),
          SizedBox(height: 12),
          TextFormField(
            controller: _observacionCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Observación (opcional)',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          SizedBox(height: 12),
          Text('Comprobante (opcional)',
              style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _tomarFoto(ImageSource.camera),
                icon: Icon(Icons.photo_camera_outlined),
                label: Text('Tomar foto'),
              ),
              SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _tomarFoto(ImageSource.gallery),
                icon: Icon(Icons.photo_library_outlined),
                label: Text('Galería'),
              ),
            ],
          ),
          if (_fotoPath != null) ...[
            SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_fotoPath!),
                height: 110,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: Icon(Icons.check_circle_outline),
            label: Text(_guardando ? 'Guardando…' : 'Guardar gasto'),
            style: FilledButton.styleFrom(minimumSize: Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}