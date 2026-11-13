/// Registro de auditoría de las operaciones críticas.
///
/// Usa la tabla `auditoria` ya existente. Todo queda trazado:
/// quién creó el pedido, quién lo asignó, quién lo entregó, cuánto cobró…
library;


import 'sb.dart';

class AuditoriaRepo {
  const AuditoriaRepo();

  /// Registra una acción. Si la auditoría falla, NO debe tumbar la operación
  /// principal: por eso se capturan los errores silenciosamente.
  Future<void> registrar({
    required String empresaId,
    required String entidad,
    required String entidadId,
    required String accion,
    String? usuarioId,
    Map<String, dynamic>? detalle,
  }) async {
    try {
      await sb.from('auditoria').insert({
        'empresa_id': empresaId,
        'entidad': entidad,
        'entidad_id': entidadId,
        'accion': accion,
        'usuario_id': usuarioId,
        'detalle': detalle,
      });
    } catch (_) {
      // La auditoría es complementaria: nunca debe romper el flujo.
    }
  }

  /// Historial de una entidad concreta.
  Future<List<Map<String, dynamic>>> porEntidad({
    required String entidad,
    required List<String> entidadIds,
    int limite = 100,
  }) async {
    if (entidadIds.isEmpty) return const [];
    final data = await sb
        .from('auditoria')
        .select('entidad, entidad_id, accion, usuario_id, fecha, detalle')
        .eq('entidad', entidad)
        .inFilter('entidad_id', entidadIds)
        .order('fecha', ascending: false)
        .limit(limite);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Historial de una sola entidad.
  Future<List<Map<String, dynamic>>> deUna({
    required String entidad,
    required String entidadId,
    int limite = 50,
  }) async {
    final data = await sb
        .from('auditoria')
        .select('entidad, entidad_id, accion, usuario_id, fecha, detalle')
        .eq('entidad', entidad)
        .eq('entidad_id', entidadId)
        .order('fecha', ascending: false)
        .limit(limite);
    return List<Map<String, dynamic>>.from(data);
  }
}

const auditoriaRepo = AuditoriaRepo();
