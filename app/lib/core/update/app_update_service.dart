import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Información de la última versión publicada.
class VersionInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String? notas;
  final bool obligatoria;

  const VersionInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.notas,
    required this.obligatoria,
  });
}

/// Verifica actualizaciones y descarga/instala el APK nuevo.
class AppUpdateService {
  AppUpdateService._();

  /// Devuelve la versión publicada más reciente, o null si no hay datos.
  static Future<VersionInfo?> fetchLatestVersion() async {
    try {
      final data = await Supabase.instance.client
          .from('app_versiones')
          .select('version_code, version_name, apk_url, notas, obligatoria')
          .eq('id', 1)
          .maybeSingle();
      if (data == null) return null;
      return VersionInfo(
        versionCode: data['version_code'] as int,
        versionName: data['version_name'] as String,
        apkUrl: data['apk_url'] as String,
        notas: data['notas'] as String?,
        obligatoria: data['obligatoria'] as bool? ?? false,
      );
    } catch (_) {
      return null; // Sin conexión o tabla vacía: la app sigue normal.
    }
  }

  /// true si la versión instalada es menor que la publicada.
  static Future<bool> hayNuevaVersion(VersionInfo remota) async {
    final info = await PackageInfo.fromPlatform();
    final local = int.tryParse(info.buildNumber) ?? 0;
    return remota.versionCode > local;
  }

  /// Descarga el APK. [onProgress] recibe 0.0–1.0.
  static Future<File> descargarApk(
    String url,
    void Function(double progreso) onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final archivo = File('${dir.path}/update.apk');

    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      throw Exception('No se pudo descargar la actualización.');
    }

    final total = response.contentLength ?? 0;
    var recibido = 0;
    final sink = archivo.openWrite();
    await for (final chunk in response.stream) {
      sink.add(chunk);
      recibido += chunk.length;
      if (total > 0) onProgress(recibido / total);
    }
    await sink.close();
    return archivo;
  }

  /// Abre el APK descargado con el instalador de Android.
  static Future<void> instalar(File apk) async {
    final result = await OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw Exception('No se pudo abrir el instalador.');
    }
  }
}
