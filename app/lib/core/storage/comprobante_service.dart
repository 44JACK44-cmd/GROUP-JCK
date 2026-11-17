/// Subida de comprobantes (fotos de Yape) al bucket `comprobantes`.
///
/// Devuelve la URL pública del archivo subido, o `null` si no se pudo subir
/// (sin conexión, permiso denegado, etc.). La app nunca bloquea la venta por
/// un fallo de subida: el pago se registra igual y la foto se reintenta.
library;

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ComprobanteService {
  ComprobanteService._();

  static const _bucket = 'comprobantes';

  static String _contentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  /// Sube un archivo local y devuelve su URL pública.
  ///
  /// Si falla (sin red, permisos), devuelve `null` sin lanzar.
  static Future<String?> subir(String localPath) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) return null;
      final ext = localPath.split('.').last.toLowerCase();
      final name = '${Uuid().v4()}.$ext';
      final path = 'yape/$name';
      final bytes = await file.readAsBytes();
      await Supabase.instance.client.storage
          .from(_bucket)
          .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: _contentType(localPath)));
      return Supabase.instance.client.storage.from(_bucket).getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }
}