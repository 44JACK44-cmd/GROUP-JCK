/// Repositorio de rendiciones: declaración de dinero y aprobación.
library;

import 'package:uuid/uuid.dart';

import 'auditoria_repo.dart';
import 'sb.dart';

/// Estado de una rendición.
class EstadoRendicion {
  static const pendiente = 'PENDIENTE';
  static const enRevision = 'EN_REVISION';
  static const conDiferencia = 'CON_DIFERENCIA';
  static const observada = 'OBSERVADA';
  static const aprobada = 'APROBADA';
}

class RendicionesRepo {
  const RendicionesRepo();

  /// El motorizado declara cuánto dinero entrega.
  Future<String> declarar({
    required String empresaId,
    required String motorizadoId,
    required double efectivoDeclarado,
    required double yapeDeclarado,
    String? observaciones,
    String? uuidOffline,
  }) async {
    final uuid = uuidOffline ?? const Uuid().v4();

    // Verificar que no exista ya una rendición para hoy
    final existente = await sb
        .from('rendiciones')
        .select('id')
        .eq('motorizado_id', motorizadoId)
        .eq('fecha', DateTime.now().toIso8601String().substring(0, 10))
        .maybeSingle();

    if (existente != null) {
      throw Exception('Ya declaraste tu rendición de hoy.');
    }

    final data = await sb
        .from('rendiciones')
        .insert({
          'empresa_id': empresaId,
          'motorizado_id': motorizadoId,
          'efectivo_declarado': efectivoDeclarado,
          'yape_declarado': yapeDeclarado,
          'observaciones': observaciones?.trim().isEmpty == true ? null : observaciones?.trim(),
          'uuid_offline': uuid,
        })
        .select('id')
        .single();

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'rendicion',
      entidadId: data['id'] as String,
      accion: 'DECLARAR',
      usuarioId: motorizadoId,
      detalle: {
        'efectivo': efectivoDeclarado,
        'yape': yapeDeclarado,
        'observaciones': observaciones,
      },
    );

    return data['id'] as String;
  }

  /// Lista rendiciones de un motorizado o de toda la empresa.
  Future<List<Map<String, dynamic>>> listar({
    String? motorizadoId,
    DateTime? desde,
    DateTime? hasta,
    String? estado,
  }) async {
    var q = sb.from('rendiciones').select(
      'id, empresa_id, motorizado_id, fecha, efectivo_declarado, yape_declarado, '
      'observaciones, hora_entrega, recibido_por, estado, diferencia, '
      'justificacion, aprobado_por, fecha_aprobacion, uuid_offline, '
      'perfiles!motorizado_id(nombre, telefono)',
    );
    if (motorizadoId != null) q = q.eq('motorizado_id', motorizadoId);
    if (desde != null) q = q.gte('fecha', desde.toIso8601String().substring(0, 10));
    if (hasta != null) q = q.lte('fecha', hasta.toIso8601String().substring(0, 10));
    if (estado != null) q = q.eq('estado', estado);
    final data = await q.order('hora_entrega', ascending: false).limit(200);
    return List<Map<String, dynamic>>.from(data);
  }

  /// El admin revisa una rendición y la aprueba, observa o rechaza.
  Future<void> revisar({
    required String empresaId,
    required String rendicionId,
    required String estado,
    required String adminId,
    String? justificacion,
    double? diferencia,
  }) async {
    final updates = <String, dynamic>{
      'estado': estado,
      'recibido_por': adminId,
    };
    if (justificacion != null && justificacion.trim().isNotEmpty) {
      updates['justificacion'] = justificacion.trim();
    }
    if (diferencia != null) {
      updates['diferencia'] = diferencia;
    }
    if (estado == EstadoRendicion.aprobada) {
      updates['aprobado_por'] = adminId;
      updates['fecha_aprobacion'] = DateTime.now().toIso8601String();
    }

    await sb.from('rendiciones').update(updates).eq('id', rendicionId);

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'rendicion',
      entidadId: rendicionId,
      accion: 'REVISAR:$estado',
      usuarioId: adminId,
      detalle: {
        'estado': estado,
        'justificacion': justificacion,
        'diferencia': diferencia,
      },
    );
  }

  /// Cierre diario: el admin cierra la jornada.
  Future<void> cerrarJornada({
    required String empresaId,
    required String adminId,
    required DateTime fecha,
    double? justificacion,
    String? observaciones,
  }) async {
    final fechaStr = fecha.toIso8601String().substring(0, 10);

    // Verificar que no exista ya un cierre para esta fecha
    final existente = await sb
        .from('cierre_diario')
        .select('id, estado')
        .eq('empresa_id', empresaId)
        .eq('fecha', fechaStr)
        .maybeSingle();

    if (existente != null && existente['estado'] == 'CERRADO') {
      throw Exception('Esta jornada ya fue cerrada.');
    }

    // Calcular totales
    final inicio = DateTime(fecha.year, fecha.month, fecha.day);
    final fin = inicio.add(const Duration(days: 1));

    final res = await Future.wait([
      sb.from('pedidos').select('id, total, estado').eq('empresa_id', empresaId).gte('fecha', inicio.toIso8601String()).lt('fecha', fin.toIso8601String()).limit(5000),
      sb.from('pagos').select('monto, metodo').eq('empresa_id', empresaId).gte('fecha', inicio.toIso8601String()).lt('fecha', fin.toIso8601String()).limit(5000),
      sb.from('gastos').select('monto').eq('empresa_id', empresaId).gte('fecha', inicio.toIso8601String()).lt('fecha', fin.toIso8601String()).limit(5000),
      sb.from('rendiciones').select('id').eq('empresa_id', empresaId).eq('fecha', fechaStr).eq('estado', 'PENDIENTE').limit(100),
    ]);

    final pedidos = List<Map<String, dynamic>>.from(res[0] as List);
    final pagos = List<Map<String, dynamic>>.from(res[1] as List);
    final gastos = List<Map<String, dynamic>>.from(res[2] as List);
    final rendicionesPendientes = (res[3] as List).length;

    var totalVentas = 0.0, efectivoEsperado = 0.0, yapeTotal = 0.0, gastosTotal = 0.0;
    var pedidosPendientes = 0;
    for (final p in pedidos) {
      final estado = p['estado'] as String? ?? '';
      final total = (p['total'] as num? ?? 0).toDouble();
      if (estado == 'ENTREGADO') totalVentas += total;
      if (estado == 'NUEVO' || estado == 'ASIGNADO' || estado == 'EN_CAMINO') pedidosPendientes++;
    }
    for (final p in pagos) {
      final monto = (p['monto'] as num? ?? 0).toDouble();
      final metodo = p['metodo'] as String? ?? 'OTRO';
      if (metodo == 'EFECTIVO') efectivoEsperado += monto;
      if (metodo == 'YAPE') yapeTotal += monto;
    }
    for (final g in gastos) {
      gastosTotal += (g['monto'] as num? ?? 0).toDouble();
    }

    final efectivoRecibido = efectivoEsperado - gastosTotal;
    final deudasTotal = (totalVentas - (efectivoEsperado + yapeTotal)) > 0
        ? totalVentas - (efectivoEsperado + yapeTotal)
        : 0.0;

    final datos = {
      'empresa_id': empresaId,
      'fecha': fechaStr,
      'total_ventas': totalVentas,
      'efectivo_esperado': efectivoEsperado,
      'efectivo_recibido': efectivoRecibido,
      'yape_total': yapeTotal,
      'deudas_total': deudasTotal,
      'gastos_total': gastosTotal,
      'rendiciones_pendientes': rendicionesPendientes,
      'diferencias': 0.0,
      'pedidos_pendientes': pedidosPendientes,
      'cerrado_por': adminId,
      'fecha_cierre': DateTime.now().toIso8601String(),
      'estado': 'CERRADO',
      if (observaciones != null && observaciones.trim().isNotEmpty) 'justificacion': observaciones.trim(),
    };

    if (existente != null) {
      await sb.from('cierre_diario').update(datos).eq('id', existente['id']);
    } else {
      await sb.from('cierre_diario').insert(datos);
    }

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'cierre_diario',
      entidadId: fechaStr,
      accion: 'CERRAR_JORNADA',
      usuarioId: adminId,
      detalle: {
        'fecha': fechaStr,
        'total_ventas': totalVentas,
        'efectivo_esperado': efectivoEsperado,
        'efectivo_recibido': efectivoRecibido,
        'yape_total': yapeTotal,
        'gastos_total': gastosTotal,
        'deudas_total': deudasTotal,
        'pedidos_pendientes': pedidosPendientes,
        'rendiciones_pendientes': rendicionesPendientes,
      },
    );
  }

  /// Verificar si una jornada está cerrada.
  Future<bool> jornadaCerrada(String empresaId, DateTime fecha) async {
    final fechaStr = fecha.toIso8601String().substring(0, 10);
    final data = await sb
        .from('cierre_diario')
        .select('estado')
        .eq('empresa_id', empresaId)
        .eq('fecha', fechaStr)
        .maybeSingle();
    return data != null && data['estado'] == 'CERRADO';
  }

  /// Obtener cierre diario de una fecha.
  Future<Map<String, dynamic>?> obtenerCierre(String empresaId, DateTime fecha) async {
    final fechaStr = fecha.toIso8601String().substring(0, 10);
    final data = await sb
        .from('cierre_diario')
        .select('*')
        .eq('empresa_id', empresaId)
        .eq('fecha', fechaStr)
        .maybeSingle();
    return data == null ? null : Map<String, dynamic>.from(data);
  }
}

const rendicionesRepo = RendicionesRepo();