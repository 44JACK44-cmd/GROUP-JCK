/// Fondo de vuelto: dinero que el administrador entrega al motorizado para
/// dar cambio al inicio de la jornada.
///
/// Puede entregarse en EFECTIVO (billetes/monedas para cambio) o por YAPE
/// (cuando el billete entregado no sirve para dar vuelto). Es dinero de la
/// empresa, NO una venta ni un cobro, y se controla aparte en la rendición.
library;

import 'package:uuid/uuid.dart';

import 'rendicion_repo.dart';
import 'sb.dart';

class FondoVueltoRepo {
  const FondoVueltoRepo();

  static const _columnas = 'id, empresa_id, motorizado_id, monto, fecha, '
      'entregado_por, observaciones, uuid_offline';

  /// Movimientos de fondo de un motorizado (o de toda la empresa) en un rango.
  Future<List<Map<String, dynamic>>> listar({
    String? motorizadoId,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    Future<List<Map<String, dynamic>>> consultar(String columnas) async {
      var q = sb.from('fondo_vuelto').select(columnas);
      if (motorizadoId != null) q = q.eq('motorizado_id', motorizadoId);
      if (desde != null) q = q.gte('fecha', desde.toIso8601String());
      if (hasta != null) q = q.lte('fecha', hasta.toIso8601String());
      return List<Map<String, dynamic>>.from(
        await q.order('fecha', ascending: false).limit(200),
      );
    }

    try {
      return await consultar('$_columnas, medio_pago');
    } catch (e) {
      if (!esColumnaAusente(e)) rethrow;
      return consultar(_columnas);
    }
  }

  /// Total de todos los fondos (informativo).
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

  /// Total entregado en EFECTIVO (sí cuenta para el efectivo esperado).
  Future<double> totalEfectivo({
    required String motorizadoId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final data = await listar(
      motorizadoId: motorizadoId,
      desde: desde,
      hasta: hasta,
    );
    return data
        .where((f) => (f['medio_pago'] as String? ?? 'EFECTIVO') == 'EFECTIVO')
        .fold<double>(0, (s, f) => s + (f['monto'] as num? ?? 0).toDouble());
  }

  /// Total entregado por YAPE (no se mezcla con el efectivo físico).
  Future<double> totalYape({
    required String motorizadoId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final data = await listar(
      motorizadoId: motorizadoId,
      desde: desde,
      hasta: hasta,
    );
    return data
        .where((f) => f['medio_pago'] == 'YAPE')
        .fold<double>(0, (s, f) => s + (f['monto'] as num? ?? 0).toDouble());
  }

  /// El administrador entrega el fondo. Idempotente por `uuid_offline`.
  Future<String> entregar({
    required String empresaId,
    required String motorizadoId,
    required String entregadoPor,
    required double monto,
    String medioPago = 'EFECTIVO',
    String? observaciones,
    String? uuidOffline,
  }) async {
    if (monto <= 0) {
      throw Exception('El monto del fondo debe ser mayor a cero.');
    }
    if (medioPago != 'EFECTIVO' && medioPago != 'YAPE') {
      throw Exception('El fondo solo puede ser EFECTIVO o YAPE.');
    }
    final uuid = uuidOffline ?? const Uuid().v4();

    final existente = await sb
        .from('fondo_vuelto')
        .select('id')
        .eq('uuid_offline', uuid)
        .maybeSingle();
    if (existente != null) return existente['id'] as String;

    final fila = <String, dynamic>{
      'empresa_id': empresaId,
      'motorizado_id': motorizadoId,
      'monto': monto,
      'medio_pago': medioPago,
      'entregado_por': entregadoPor,
      'observaciones':
          observaciones?.trim().isEmpty == true ? null : observaciones?.trim(),
      'uuid_offline': uuid,
    };

    try {
      final data = await sb
          .from('fondo_vuelto')
          .insert(fila)
          .select('id')
          .single();
      return data['id'] as String;
    } catch (e) {
      if (!esColumnaAusente(e)) rethrow;
      final sinMedio = Map<String, dynamic>.from(fila)..remove('medio_pago');
      final data = await sb
          .from('fondo_vuelto')
          .insert(sinMedio)
          .select('id')
          .single();
      return data['id'] as String;
    }
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
