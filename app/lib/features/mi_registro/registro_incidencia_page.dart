/// Registro rápido de fallas e incidencias del motorizado.
///
/// La foto es opcional y se guarda en Supabase Storage. Sin conexión queda en
/// la cola offline con la ruta local y se sube al sincronizar.
library;

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

class RegistroIncidenciaPage extends ConsumerStatefulWidget {
  RegistroIncidenciaPage({super.key});

  @override
  ConsumerState<RegistroIncidenciaPage> createState() =>
      _RegistroIncidenciaPageState();
}

class _RegistroIncidenciaPageState extends ConsumerState<RegistroIncidenciaPage> {
  final _descripcionCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  String _tipo = 'FALLA';
  String? _fotoPath;
  bool _guardando = false;

  static const _tipos = <String, IconData>{
    'FALLA': Icons.report_problem_outlined,
    'REPARACION': Icons.build_outlined,
    'MANTENIMIENTO': Icons.handyman_outlined,
    'ESTACIONAMIENTO': Icons.local_parking_outlined,
    'PEAJE': Icons.toll_outlined,
    'OTRO': Icons.notes_outlined,
  };

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _montoCtrl.dispose();
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la cámara.')),
        );
      }
    }
  }

  Future<void> _guardar() async {
    final descripcion = _descripcionCtrl.text.trim();
    if (descripcion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Escribe una descripción.')),
      );
      return;
    }
    final monto = double.tryParse(_montoCtrl.text.replaceAll(',', '.')) ?? 0;

    setState(() => _guardando = true);
    final auth = ref.read(authProvider);
    final datos = <String, dynamic>{
      'empresa_id': auth.empresaId,
      'usuario_id': auth.usuarioId,
      'tipo': _tipo,
      'descripcion': descripcion,
      'monto': monto,
      'uuid_offline': Uuid().v4(),
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
          await sb.from('incidencias').insert(fila);
        } catch (e) {
          if (esErrorDeRed(e)) rethrow;
          if (!esColumnaAusente(e)) rethrow;
          final sinFoto = Map<String, dynamic>.from(fila)
            ..remove('comprobante_url');
          await sb.from('incidencias').insert(sinFoto);
        }
        SyncBus.dineroCambio();
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Incidencia registrada.')),
        );
        return;
      } catch (e) {
        if (!esErrorDeRed(e)) {
          if (!mounted) return;
          setState(() => _guardando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(traducirError(e, contexto: 'No pudimos registrar').mensaje),
            ),
          );
          return;
        }
      }
    }

    await Outbox.encolarIncidencia(
      incidencia: datos,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Registrar falla')),
      body: ListView(
        padding: EdgeInsets.all(20),
        children: [
          Text('Tipo de falla', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _tipos.entries)
                ChoiceChip(
                  avatar: Icon(e.value, size: 18),
                  label: Text(e.key[0] + e.key.substring(1).toLowerCase()),
                  selected: _tipo == e.key,
                  selectedColor: AppTheme.primary.withValues(alpha: 0.12),
                  onSelected: (v) => setState(() => _tipo = v ? e.key : _tipo),
                ),
            ],
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _descripcionCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Descripción *',
              prefixIcon: Icon(Icons.description_outlined),
            ),
          ),
          SizedBox(height: 12),
          TextFormField(
            controller: _montoCtrl,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monto (opcional)',
              prefixText: 'S/ ',
              prefixIcon: Icon(Icons.attach_money),
            ),
          ),
          SizedBox(height: 12),
          Text('Foto (opcional)', style: Theme.of(context).textTheme.titleSmall),
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
            label: Text(_guardando ? 'Guardando…' : 'Guardar falla'),
            style: FilledButton.styleFrom(minimumSize: Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}