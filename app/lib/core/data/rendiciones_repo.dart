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

/// Totales de una jornada, calculados solo con datos reales.
class CierreCalculado {
  /// Solo pedidos ENTREGADO. Nunca lo pendiente ni lo cancelado.
  final double totalVentas;

  /// Cobros en efectivo del día (de `pagos`).
  final double efectivoEsperado;

  /// Cobros por Yape del día.
  final double yapeTotal;

  /// Gastos pagados en efectivo (los únicos que descuentan del efectivo).
  final double gastosEfectivo;

  /// Todos los gastos del día, sin importar con qué se pagaron.
  final double gastosTotal;

  /// Lo que debería quedar en efectivo: cobrado en efectivo − gastos en efectivo.
  final double efectivoNeto;

  /// Lo que el motorizado declaró (suma de rendiciones), o el neto si no hay.
  final double efectivoRecibido;

  /// Declarado − neto. Positivo = sobra; negativo = falta.
  final double diferencias;

  /// Ventas entregadas que todavía no se cobraron.
  final double deudasTotal;

  final int pedidosPendientes;
  final int rendicionesPendientes;

  const CierreCalculado({
    this.totalVentas = 0,
    this.efectivoEsperado = 0,
    this.yapeTotal = 0,
    this.gastosEfectivo = 0,
    this.gastosTotal = 0,
    this.efectivoNeto = 0,
    this.efectivoRecibido = 0,
    this.diferencias = 0,
    this.deudasTotal = 0,
    this.pedidosPendientes = 0,
    this.rendicionesPendientes = 0,
  });
}

/// Cálculo puro del cierre diario (sin base de datos, fácil de probar).
class CalculoCierre {
  const CalculoCierre._();

  static CierreCalculado calcular({
    required List<Map<String, dynamic>> pedidos,
    required List<Map<String, dynamic>> pagos,
    required List<Map<String, dynamic>> gastos,
    required List<Map<String, dynamic>> rendiciones,
  }) {
    var totalVentas = 0.0, efectivoEsperado = 0.0, yapeTotal = 0.0;
    var gastosTotal = 0.0, gastosEfectivo = 0.0;
    var pedidosPendientes = 0;

    for (final p in pedidos) {
      final estado = p['estado'] as String? ?? '';
      final total = (p['total'] as num? ?? 0).toDouble();
      // Regla: una venta solo cuenta cuando el pedido fue ENTREGADO.
      if (estado == 'ENTREGADO') totalVentas += total;
      if (estado == 'NUEVO' || estado == 'ASIGNADO' || estado == 'EN_CAMINO') {
        pedidosPendientes++;
      }
    }

    for (final p in pagos) {
      final monto = (p['monto'] as num? ?? 0).toDouble();
      final metodo = p['metodo'] as String? ?? 'OTRO';
      if (metodo == 'EFECTIVO') efectivoEsperado += monto;
      if (metodo == 'YAPE') yapeTotal += monto;
    }

    // Regla: el gasto descuenta del bolsillo con el que se pagó.
    for (final g in gastos) {
      final monto = (g['monto'] as num? ?? 0).toDouble();
      gastosTotal += monto;
      if ((g['medio_pago'] as String? ?? 'EFECTIVO') == 'EFECTIVO') {
        gastosEfectivo += monto;
      }
    }

    var efectivoDeclarado = 0.0;
    for (final r in rendiciones) {
      efectivoDeclarado += (r['efectivo_declarado'] as num? ?? 0).toDouble();
    }

    final efectivoNeto = efectivoEsperado - gastosEfectivo;
    final hayRendiciones = rendiciones.isNotEmpty;
    final efectivoRecibido = hayRendiciones ? efectivoDeclarado : efectivoNeto;
    final diferencias = hayRendiciones ? efectivoDeclarado - efectivoNeto : 0.0;
    final cobrado = efectivoEsperado + yapeTotal;
    final deudasTotal = (totalVentas - cobrado) > 0 ? totalVentas - cobrado : 0.0;

    return CierreCalculado(
      totalVentas: totalVentas,
      efectivoEsperado: efectivoEsperado,
      yapeTotal: yapeTotal,
      gastosEfectivo: gastosEfectivo,
      gastosTotal: gastosTotal,
      efectivoNeto: efectivoNeto,
      efectivoRecibido: efectivoRecibido,
      diferencias: diferencias,
      deudasTotal: deudasTotal,
      pedidosPendientes: pedidosPendientes,
      rendicionesPendientes:
          rendiciones.where((r) => r['estado'] == 'PENDIENTE').length,
    );
  }
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
    // Una rendición aprobada es definitiva: no se puede reabrir ni corregir,
    // para que el dinero ya entregado no cambie de valor después.
    final actual = await sb
        .from('rendiciones')
        .select('estado')
        .eq('id', rendicionId)
        .maybeSingle();
    if (actual == null) throw Exception('La rendición ya no existe.');
    if (actual['estado'] == EstadoRendicion.aprobada) {
      throw Exception('Esta rendición ya fue aprobada y no se puede modificar.');
    }

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

    final filas = await sb
        .from('rendiciones')
        .update(updates)
        .eq('id', rendicionId)
        .select('id');

    if (List<Map<String, dynamic>>.from(filas).isEmpty) {
      throw Exception('La rendición ya no existe o no tienes permiso para revisarla.');
    }

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

    // Calcular totales del día. El "día" es local (Perú) y se convierte a UTC
    // para no correr la ventana 5 horas.
    final inicioLocal = DateTime(fecha.year, fecha.month, fecha.day);
    final finLocal = inicioLocal.add(const Duration(days: 1));
    final inicioIso = inicioLocal.toUtc().toIso8601String();
    final finIso = finLocal.toUtc().toIso8601String();

    final res = await Future.wait([
      sb.from('pedidos').select('id, total, estado').eq('empresa_id', empresaId).gte('fecha', inicioIso).lt('fecha', finIso).limit(5000),
      sb.from('pagos').select('monto, metodo').eq('empresa_id', empresaId).gte('fecha', inicioIso).lt('fecha', finIso).limit(5000),
      sb.from('gastos').select('monto, medio_pago').eq('empresa_id', empresaId).gte('fecha', inicioIso).lt('fecha', finIso).limit(5000),
      sb.from('rendiciones').select('id, efectivo_declarado, estado').eq('empresa_id', empresaId).eq('fecha', fechaStr).limit(100),
    ]);

    final pedidos = List<Map<String, dynamic>>.from(res[0] as List);
    final pagos = List<Map<String, dynamic>>.from(res[1] as List);
    final gastos = List<Map<String, dynamic>>.from(res[2] as List);
    final rendiciones = List<Map<String, dynamic>>.from(res[3] as List);

    final cierre = CalculoCierre.calcular(
      pedidos: pedidos,
      pagos: pagos,
      gastos: gastos,
      rendiciones: rendiciones,
    );

    // No se cierra la jornada con dinero sin cuadrar: si hay rendiciones
    // pendientes se ocultaría un faltante real.
    if (cierre.rendicionesPendientes > 0) {
      throw Exception(
        'Hay ${cierre.rendicionesPendientes} rendición(es) pendiente(s) de '
        'revisión. Apruébalas o recházalas antes de cerrar la jornada.',
      );
    }

    final datos = {
      'empresa_id': empresaId,
      'fecha': fechaStr,
      'total_ventas': cierre.totalVentas,
      'efectivo_esperado': cierre.efectivoEsperado,
      'efectivo_recibido': cierre.efectivoRecibido,
      'yape_total': cierre.yapeTotal,
      'deudas_total': cierre.deudasTotal,
      'gastos_total': cierre.gastosTotal,
      'rendiciones_pendientes': cierre.rendicionesPendientes,
      'diferencias': cierre.diferencias,
      'pedidos_pendientes': cierre.pedidosPendientes,
      'cerrado_por': adminId,
      'fecha_cierre': DateTime.now().toUtc().toIso8601String(),
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
        'total_ventas': cierre.totalVentas,
        'efectivo_esperado': cierre.efectivoEsperado,
        'efectivo_recibido': cierre.efectivoRecibido,
        'yape_total': cierre.yapeTotal,
        'gastos_total': cierre.gastosTotal,
        'deudas_total': cierre.deudasTotal,
        'pedidos_pendientes': cierre.pedidosPendientes,
        'rendiciones_pendientes': cierre.rendicionesPendientes,
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