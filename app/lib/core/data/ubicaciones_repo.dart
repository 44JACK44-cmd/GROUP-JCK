/// Ubicación de los motorizados para el seguimiento del admin.
///
/// Una sola fila por motorizado (`usuario_id` es la clave). El motorizado solo
/// escribe la suya; el admin de la empresa lee todas. La app nunca muestra
/// "en vivo" si la última actualización es vieja: la frescura se calcula con
/// [EstadoUbicacion].
library;

import 'sb.dart';

/// Cuánto tiempo se considera "en vivo" sin actualizar.
const Duration frescuraUbicacion = Duration(minutes: 2);

enum EstadoUbicacion {
  activo('En vivo'),
  reciente('Hace poco'),
  sinActualizar('Sin actualizar'),
  sinUbicacion('Sin ubicación');

  EstadoUbicacion(this.label);

  final String label;

  static EstadoUbicacion desde(DateTime? actualizadoEn) {
    if (actualizadoEn == null) return EstadoUbicacion.sinUbicacion;
    final diff = DateTime.now().difference(actualizadoEn);
    if (diff <= frescuraUbicacion) return EstadoUbicacion.activo;
    if (diff <= Duration(minutes: 10)) return EstadoUbicacion.reciente;
    return EstadoUbicacion.sinActualizar;
  }
}

class UbicacionMotorizado {
  final String usuarioId;
  final double latitud;
  final double longitud;
  final double? precision;
  final DateTime actualizadoEn;

  const UbicacionMotorizado({
    required this.usuarioId,
    required this.latitud,
    required this.longitud,
    required this.actualizadoEn,
    this.precision,
  });

  EstadoUbicacion get estado => EstadoUbicacion.desde(actualizadoEn);

  String get haceTexto {
    final d = DateTime.now().difference(actualizadoEn);
    if (d.inSeconds < 60) return 'hace ${d.inSeconds} s';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    return 'hace ${(d.inMinutes / 60).floor()} h';
  }
}

class UbicacionesRepo {
  const UbicacionesRepo();

  static const _tabla = 'ubicaciones_motorizado';

  /// Guarda (o reemplaza) la ubicación del usuario actual.
  Future<void> guardar({
    required String usuarioId,
    required String empresaId,
    required double latitud,
    required double longitud,
    double? precision,
  }) async {
    await sb.from(_tabla).upsert({
      'usuario_id': usuarioId,
      'empresa_id': empresaId,
      'latitud': latitud,
      'longitud': longitud,
      'precision_m': precision,
      'actualizado_en': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Todas las ubicaciones de la empresa (el admin las ve todas).
  Future<List<UbicacionMotorizado>> listar() async {
    try {
      final data = await sb
          .from(_tabla)
          .select('usuario_id, latitud, longitud, precision_m, actualizado_en')
          .order('actualizado_en', ascending: false)
          .limit(200);
      return [
        for (final u in data)
          UbicacionMotorizado(
            usuarioId: u['usuario_id'] as String,
            latitud: (u['latitud'] as num).toDouble(),
            longitud: (u['longitud'] as num).toDouble(),
            precision: (u['precision_m'] as num?)?.toDouble(),
            actualizadoEn: DateTime.tryParse(u['actualizado_en'] as String? ?? '')?.toLocal() ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Ubicación de un motorizado concreto.
  Future<UbicacionMotorizado?> de(String usuarioId) async {
    try {
      final u = await sb
          .from(_tabla)
          .select('usuario_id, latitud, longitud, precision_m, actualizado_en')
          .eq('usuario_id', usuarioId)
          .maybeSingle();
      if (u == null) return null;
      return UbicacionMotorizado(
        usuarioId: u['usuario_id'] as String,
        latitud: (u['latitud'] as num).toDouble(),
        longitud: (u['longitud'] as num).toDouble(),
        precision: (u['precision_m'] as num?)?.toDouble(),
        actualizadoEn: DateTime.tryParse(u['actualizado_en'] as String? ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }

  /// Borra la ubicación (el motorizado dejó de compartir).
  Future<void> borrar(String usuarioId) async {
    try {
      await sb.from(_tabla).delete().eq('usuario_id', usuarioId);
    } catch (_) {}
  }
}

const ubicacionesRepo = UbicacionesRepo();