/// Fondo de vuelto: dinero que el administrador entrega al motorizado para
/// dar cambio al inicio de la jornada.
///
/// NO es una venta ni un ingreso: es dinero que sale de caja y debe volver
/// en la rendición. Por eso vive en su propia tabla y no en `pagos`.
library;

import 'package:uuid/uuid.dart';

import 'rendicion_repo.dart';
import 'sb.dart';

class FondoVueltoRepo {
  const FondoVueltoRepo();

  /// Movimientos de fondo de un motorizado (o de toda la empresa) en un rango.
  Future<List<Map<String, dynamic>>> listar({
    String? motorizadoId,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    var q = sb.from('fondo_vuelto').select(
          'id, empresa_id, motorizado_id, monto, fecha, entregado_por, '
          'observaciones, uuid_offline',
        );
    if (motorizadoId != null) q = q.eq('motorizado_id', motorizadoId);
    if (desde != null) q = q.gte('fecha', desde.toIso8601String());
    if (hasta != null) q = q.lte('fecha', hasta.toIso8601String());
    final data = await q.order('fecha', ascending: false).limit(200);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Total entregado como fondo en un rango.
  Future<double> total({
    required String motorizadoId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final data = await listar(
      motorizadoId: motorizadoId,
      desde: desde,
      hasta: hasta,
    );
    return data.fold<double>(
      0,
      (s, f) => s + (f['monto'] as num? ?? 0).toDouble(),
    );
  }

  /// El administrador entrega el fondo. Idempotente por `uuid_offline`.
  Future<String> entregar({
    required String empresaId,
    required String motorizadoId,
    required String entregadoPor,
    required double monto,
    String? observaciones,
    String? uuidOffline,
  }) async {
    if (monto <= 0) {
      throw Exception('El monto del fondo debe ser mayor a cero.');
    }
    final uuid = uuidOffline ?? const Uuid().v4();

    final existente = await sb
        .from('fondo_vuelto')
        .select('id')
        .eq('uuid_offline', uuid)
        .maybeSingle();
    if (existente != null) return existente['id'] as String;

    final data = await sb
        .from('fondo_vuelto')
        .insert({
          'empresa_id': empresaId,
          'motorizado_id': motorizadoId,
          'monto': monto,
          'entregado_por': entregadoPor,
          'observaciones':
              observaciones?.trim().isEmpty == true ? null : observaciones?.trim(),
          'uuid_offline': uuid,
        })
        .select('id')
        .single();
    return data['id'] as String;
  }

  /// Resumen rápido para una pantalla: fondo, esperado y diferencia.
  Future<Rendicion> resumenJornada({
    required String motorizadoId,
    required DateTime desde,
    required DateTime hasta,
  }) {
    return rendicionRepo.calcular(
      desde: desde,
      hasta: hasta,
      motorizadoId: motorizadoId,
    );
  }
}

const fondoVueltoRepo = FondoVueltoRepo();
