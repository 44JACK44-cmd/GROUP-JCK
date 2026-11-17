/// Selector de foto de comprobante reutilizable.
///
/// Se usa en entregas, pagos de deuda y cobros sueltos. Nunca muestra emojis:
/// iconos Material, texto claro y aviso cuando falta la evidencia.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';

class ComprobantePicker extends StatelessWidget {
  final String? fotoPath;
  final ValueChanged<String?> onChanged;
  final bool obligatorio;

  const ComprobantePicker({
    super.key,
    required this.fotoPath,
    required this.onChanged,
    this.obligatorio = true,
  });

  Future<void> _tomar(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1280,
      );
      if (x != null) onChanged(x.path);
    } catch (_) {
      // Sin cámara o permiso: el usuario puede elegir de la galería.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_camera_outlined, size: 18, color: Colors.black54),
            const SizedBox(width: 8),
            Text(
              obligatorio ? 'Foto del comprobante *' : 'Foto del comprobante (opcional)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (fotoPath != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(fotoPath!),
              height: 120,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Quitar foto'),
            ),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _tomar(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 19),
                  label: const Text('Tomar foto'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _tomar(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 19),
                  label: const Text('Galería'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                ),
              ),
            ],
          ),
          if (obligatorio)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Necesaria para dejar evidencia del pago por Yape.',
                style: TextStyle(fontSize: 12, color: AppTheme.info),
              ),
            ),
        ],
      ],
    );
  }
}
