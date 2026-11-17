/// Rendición de cuentas por motorizado.
///
/// Toda la información sale de los registros reales: `pedidos`, `entregas`,
/// `pagos`, `movimiento_bal_on`, `movimiento_fierro`, `combustible`,
/// `gastos`, `fondo_vuelto` y `rendiciones`. No hay datos ficticios.
///
/// Regla del dinero:
///   fondo inicial + efectivo cobrado − gastos en efectivo = efectivo esperado
///   diferencia = efectivo declarado − efectivo esperado
///
/// El Yape y la deuda NUNCA se suman al efectivo.
library;

import 'sb.dart';

/// Resumen de un periodo para un motorizado (o para toda la empresa).
class Rendicion {
  final int pedidosRealizados;
  final int entregados;
  final int noEntregados;
  final int cancelados;
  final int pendientes;

  final double totalACobrar;
  final double cobrado;
  final double pendiente;

  final double yape;
  final double efectivo;
  final double otros;

  final double deudasGeneradas;

  final int balonesVaciosRecibidos;
  final int balonesVaciosPendientes;
  final int fierrosPendientes;

  /// Balones llenos que salieron en el periodo.
  final int balonesEntregados;

  /// Balones vacíos que volvieron en el periodo.
  final int balonesDevueltos;

  /// Pedidos registrados por el motorizado (cuaderno digital).
  final int pedidosManuales;

  /// Fallas/incidencias de la jornada y su costo.
  final int incidencias;
  final double incidenciasTotal;

  final double combustible;

  // Gastos por medio de pago
  final double gastosEfectivo;
  final double gastosYape;
  final double gastosOtros;
  final double gastosTotal;

  // Fondo de vuelto y cierre
  /// Fondo entregado en EFECTIVO (sí se cuenta en el efectivo esperado).
  final double fondoInicial;

  /// Fondo enviado por YAPE (no se mezcla con el efectivo físico).
  final double fondoYape;
  final double efectivoEsperado;

  /// Efectivo + Yape realmente cobrados en la jornada.
  final double totalRecibido;

  /// Total de gastos de la jornada (cualquier medio).
  final double totalGastos;

  /// Dinero que debería quedar: total recibido − total de gastos.
  final double dineroEsperado;

  /// Compatibilidad con pantallas anteriores: mismo valor que [dineroEsperado].
  final double totalEsperado;
  final double efectivoDeclarado;

  /// Gastos agrupados por categoría (Combustible, Peaje, ...).
  final Map<String, double> gastosPorCategoria;
  final double diferencia;
  final bool hayDeclaracion;

  const Rendicion({
    this.pedidosRealizados = 0,
    this.entregados = 0,
    this.noEntregados = 0,
    this.cancelados = 0,
    this.pendientes = 0,
    this.totalACobrar = 0,
    this.cobrado = 0,
    this.pendiente = 0,
    this.yape = 0,
    this.efectivo = 0,
    this.otros = 0,
    this.deudasGeneradas = 0,
    this.balonesVaciosRecibidos = 0,
    this.balonesVaciosPendientes = 0,
    this.fierrosPendientes = 0,
    this.balonesEntregados = 0,
    this.balonesDevueltos = 0,
    this.pedidosManuales = 0,
    this.incidencias = 0,
    this.incidenciasTotal = 0,
    this.combustible = 0,
    this.gastosEfectivo = 0,
    this.gastosYape = 0,
    this.gastosOtros = 0,
    this.gastosTotal = 0,
    this.fondoInicial = 0,
    this.fondoYape = 0,
    this.efectivoEsperado = 0,
    this.totalRecibido = 0,
    this.totalGastos = 0,
    this.dineroEsperado = 0,
    this.totalEsperado = 0,
    this.efectivoDeclarado = 0,
    this.gastosPorCategoria = const {},
    this.diferencia = 0,
    this.hayDeclaracion = false,
  });

  /// Una jornada está vacía solo si no hubo pedidos, cobros, gastos ni fondo.
  bool get vacio =>
      pedidosRealizados == 0 &&
      cobrado <= 0.009 &&
      gastosTotal <= 0.009 &&
      fondoInicial <= 0.009 &&
      fondoYape <= 0.009 &&
      incidencias == 0;

  /// Sobra dinero (positivo) o falta dinero (negativo).
  bool get tieneDiferencia => hayDeclaracion && diferencia.abs() > 0.009;
}

class RendicionRepo {
  const RendicionRepo();

  /// Efectivo que debería quedar en el bolsillo al final de la jornada.
  static double calcularEsperado({
    required double fondoInicial,
    required double efectivoCobrado,
    required double gastosEfectivo,
  }) {
    final esperado = fondoInicial + efectivoCobrado - gastosEfectivo;
    return esperado > 0 ? esperado : 0;
  }

  /// Diferencia entre lo declarado y lo esperado.
  /// Positivo = sobra; negativo = falta.
  static double calcularDiferencia({
    required double declarado,
    required double esperado,
  }) =>
      declarado - esperado;

  /// Saldo de fierros de un periodo: entregados − devueltos.
  ///
  /// El fierro y el balón vacío son el mismo activo retornable: si el cliente
  /// devolvió más de lo que se le dejó, el saldo es 0 (nunca negativo).
  static int saldoFierros(List<Map<String, dynamic>> movimientos) {
    var entregados = 0;
    var devueltos = 0;
    for (final m in movimientos) {
      final cant = (m['cantidad'] as num? ?? 0).toInt();
      if (cant <= 0) continue;
      if (m['tipo'] == 'ENTREGA') entregados += cant;
      if (m['tipo'] == 'DEVOLUCION') devueltos += cant;
    }
    final saldo = entregados - devueltos;
    return saldo > 0 ? saldo : 0;
  }

  /// Calcula la rendición de un periodo.
  ///
  /// - [motorizadoId] filtra por motorizado asignado (null = toda la empresa).
  Future<Rendicion> calcular({
    required DateTime desde,
    required DateTime hasta,
    String? motorizadoId,
  }) async {
    final hastaIso = hasta.toIso8601String();

    // 1. Pedidos del periodo. Puede no haber ninguno y aun así existir fondo
    //    o gastos: la rendición NO puede quedar vacía en ese caso.
    final pedidos = <Map<String, dynamic>>[];
    Future<List<Map<String, dynamic>>> consultarPedidos(String columnas) async {
      var q = sb
          .from('pedidos')
          .select(columnas)
          .gte('fecha', desde.toIso8601String())
          .lte('fecha', hastaIso);
      if (motorizadoId != null) q = q.eq('repartidor_id', motorizadoId);
      return List<Map<String, dynamic>>.from(await q.limit(5000));
    }

    const conOrigen =
        'id, numero, total, estado, cliente_id, repartidor_id, fecha, origen';
    const sinOrigen =
        'id, numero, total, estado, cliente_id, repartidor_id, fecha';
    try {
      pedidos.addAll(await consultarPedidos(conOrigen));
    } catch (e) {
      if (!esColumnaAusente(e)) rethrow;
      pedidos.addAll(await consultarPedidos(sinOrigen));
    }

    final pedidosIds = pedidos.map((p) => p['id'] as String).toList();

    // 2. Entregas, pagos y movimientos de esos pedidos.
    var entregas = <Map<String, dynamic>>[];
    var pagos = <Map<String, dynamic>>[];
    var movBalones = <Map<String, dynamic>>[];
    var movFierros = <Map<String, dynamic>>[];
    if (pedidosIds.isNotEmpty) {
      final res = await Future.wait([
        sb
            .from('entregas')
            .select('pedido_id, estado_bal_on_vacio, estado_pago')
            .inFilter('pedido_id', pedidosIds)
            .limit(5000),
        sb
            .from('pagos')
            .select('pedido_id, monto, metodo')
            .inFilter('pedido_id', pedidosIds)
            .limit(10000),
        sb
            .from('movimiento_bal_on')
            .select('cliente_id, tipo, cantidad, usuario_id, fecha')
            .inFilter('pedido_id', pedidosIds)
            .limit(10000),
        sb
            .from('movimiento_fierro')
            .select('cliente_id, tipo, cantidad, usuario_id, fecha')
            .inFilter('pedido_id', pedidosIds)
            .limit(10000),
      ]);
      entregas = List<Map<String, dynamic>>.from(res[0] as List);
      pagos = List<Map<String, dynamic>>.from(res[1] as List);
      movBalones = List<Map<String, dynamic>>.from(res[2] as List);
      movFierros = List<Map<String, dynamic>>.from(res[3] as List);
    }

    // 3. Gastos del motorizado en el periodo (con medio de pago).
    var gastosData = <Map<String, dynamic>>[];
    if (motorizadoId != null) {
      try {
        final g = await sb
            .from('gastos')
            .select('monto, medio_pago, categoria')
            .eq('usuario_id', motorizadoId)
            .gte('fecha', desde.toIso8601String())
            .lte('fecha', hastaIso)
            .limit(500);
        gastosData = List<Map<String, dynamic>>.from(g);
      } catch (e) {
        if (!esPermisoDenegado(e) && !esColumnaAusente(e)) rethrow;
      }
    }

    // 3b. Fallas e incidencias de la jornada.
    var incidenciasData = <Map<String, dynamic>>[];
    if (motorizadoId != null) {
      try {
        final i = await sb
            .from('incidencias')
            .select('monto')
            .eq('usuario_id', motorizadoId)
            .gte('fecha', desde.toIso8601String())
            .lte('fecha', hastaIso)
            .limit(200);
        incidenciasData = List<Map<String, dynamic>>.from(i);
      } catch (e) {
        if (!esPermisoDenegado(e) && !esTablaAusente(e)) rethrow;
      }
    }
    final incidenciasTotal = incidenciasData.fold<double>(
      0,
      (s, i) => s + (i['monto'] as num? ?? 0).toDouble(),
    );

    // 4. Fondo de vuelto. Solo el EFECTIVO suma al efectivo esperado:
    //    un vuelto enviado por Yape NO es dinero físico en el bolsillo.
    var fondoInicial = 0.0;
    var fondoYape = 0.0;
    if (motorizadoId != null) {
      try {
        final f = await sb
            .from('fondo_vuelto')
            .select('monto, medio_pago')
            .eq('motorizado_id', motorizadoId)
            .gte('fecha', desde.toIso8601String())
            .lte('fecha', hastaIso)
            .limit(500);
        for (final fila in f) {
          final monto = (fila['monto'] as num? ?? 0).toDouble();
          if (fila['medio_pago'] == 'YAPE') {
            fondoYape += monto;
          } else {
            fondoInicial += monto;
          }
        }
      } catch (e) {
        if (esColumnaAusente(e)) {
          // Base sin paso 17: todo se consideraba efectivo (compatibilidad).
          final f = await sb
              .from('fondo_vuelto')
              .select('monto')
              .eq('motorizado_id', motorizadoId)
              .gte('fecha', desde.toIso8601String())
              .lte('fecha', hastaIso)
              .limit(500);
          for (final fila in f) {
            fondoInicial += (fila['monto'] as num? ?? 0).toDouble();
          }
        } else if (!esPermisoDenegado(e) && !esTablaAusente(e)) {
          rethrow;
        }
      }
    }

    // 5. Rendiciones declaradas en el periodo.
    var efectivoDeclarado = 0.0;
    var hayDeclaracion = false;
    if (motorizadoId != null) {
      try {
        final r = await sb
            .from('rendiciones')
            .select('efectivo_declarado, estado, fecha')
            .eq('motorizado_id', motorizadoId)
            .gte('fecha', desde.toIso8601String().substring(0, 10))
            .lte('fecha', hastaIso.substring(0, 10))
            .limit(100);
        for (final fila in r) {
          efectivoDeclarado += (fila['efectivo_declarado'] as num? ?? 0).toDouble();
          hayDeclaracion = true;
        }
      } catch (e) {
        if (!esPermisoDenegado(e) && !esTablaAusente(e)) rethrow;
      }
    }

    // 6. Totales por estado.
    var entregados = 0, noEntregados = 0, cancelados = 0, pendientes = 0;
    var pedidosManuales = 0;
    var totalACobrar = 0.0;
    for (final p in pedidos) {
      if (p['origen'] == 'MOTORIZADO') pedidosManuales++;
      final estado = p['estado'] as String? ?? '';
      final total = (p['total'] as num? ?? 0).toDouble();
      switch (estado) {
        case 'ENTREGADO':
          entregados++;
          totalACobrar += total;
          break;
        case 'NO_ENTREGADO':
          noEntregados++;
          break;
        case 'CANCELADO':
          cancelados++;
          break;
        default:
          pendientes++;
      }
    }

    // 7. Cobrado por método. La deuda no es efectivo ni Yape.
    var cobrado = 0.0, yape = 0.0, efectivo = 0.0, otros = 0.0;
    for (final p in pagos) {
      final monto = (p['monto'] as num? ?? 0).toDouble();
      final metodo = p['metodo'] as String? ?? 'OTRO';
      cobrado += monto;
      switch (metodo) {
        case 'YAPE':
          yape += monto;
          break;
        case 'EFECTIVO':
          efectivo += monto;
          break;
        default:
          otros += monto;
      }
    }

    // 8. Balones: salieron llenos, volvieron vacíos.
    var vaciosRecibidos = 0;
    var balonesEntregados = 0;
    final clientesConPendiente = <String>{};
    for (final m in movBalones) {
      final cant = (m['cantidad'] as num? ?? 0).toInt();
      if (m['tipo'] == 'ENTREGA_LLENO') balonesEntregados += cant;
      if (m['tipo'] == 'DEVOLUCION_VACIO') vaciosRecibidos += cant;
    }
    for (final e in entregas) {
      if (e['estado_bal_on_vacio'] == 'NO_RECIBIDO') {
        // El cliente queda debiendo el vacío hasta que lo devuelva.
        final pedido = pedidos.firstWhere(
          (p) => p['id'] == e['pedido_id'],
          orElse: () => const {},
        );
        final clienteId = pedido['cliente_id'] as String?;
        if (clienteId != null) clientesConPendiente.add(clienteId);
      }
    }

    final fierrosPendientes = RendicionRepo.saldoFierros(movFierros);

    // 9. Combustible del motorizado en el periodo.
    var combustible = 0.0;
    if (motorizadoId != null) {
      try {
        final comb = await sb
            .from('combustible')
            .select('monto')
            .eq('usuario_id', motorizadoId)
            .gte('fecha', desde.toIso8601String())
            .lte('fecha', hastaIso)
            .limit(500);
        for (final c in comb) {
          combustible += (c['monto'] as num? ?? 0).toDouble();
        }
      } catch (e) {
        if (!esPermisoDenegado(e)) rethrow;
      }
    }

    final pendiente = (totalACobrar - cobrado) > 0 ? totalACobrar - cobrado : 0.0;

    // 10. Gastos por medio de pago y por categoría.
    var gastosEfectivo = 0.0, gastosYape = 0.0, gastosOtros = 0.0;
    final porCategoria = <String, double>{};
    for (final g in gastosData) {
      final monto = (g['monto'] as num? ?? 0).toDouble();
      final categoria = (g['categoria'] as String?)?.trim().isEmpty == false
          ? g['categoria'] as String
          : 'Otros';
      porCategoria[categoria] = (porCategoria[categoria] ?? 0) + monto;
      switch (g['medio_pago'] as String? ?? 'EFECTIVO') {
        case 'YAPE':
          gastosYape += monto;
          break;
        case 'OTRO':
          gastosOtros += monto;
          break;
        default:
          gastosEfectivo += monto;
      }
    }
    final gastosTotal = gastosEfectivo + gastosYape + gastosOtros;

    final efectivoEsperado = calcularEsperado(
      fondoInicial: fondoInicial,
      efectivoCobrado: efectivo,
      gastosEfectivo: gastosEfectivo,
    );
    final diferencia = hayDeclaracion
        ? calcularDiferencia(declarado: efectivoDeclarado, esperado: efectivoEsperado)
        : 0.0;

    return Rendicion(
      pedidosRealizados: pedidos.length,
      entregados: entregados,
      noEntregados: noEntregados,
      cancelados: cancelados,
      pendientes: pendientes,
      totalACobrar: totalACobrar,
      cobrado: cobrado,
      pendiente: pendiente,
      yape: yape,
      efectivo: efectivo,
      otros: otros,
      deudasGeneradas: pendiente,
      balonesVaciosRecibidos: vaciosRecibidos,
      balonesVaciosPendientes: clientesConPendiente.length,
      fierrosPendientes: fierrosPendientes,
      balonesEntregados: balonesEntregados,
      balonesDevueltos: vaciosRecibidos,
      pedidosManuales: pedidosManuales,
      incidencias: incidenciasData.length,
      incidenciasTotal: incidenciasTotal,
      combustible: combustible,
      gastosEfectivo: gastosEfectivo,
      gastosYape: gastosYape,
      gastosOtros: gastosOtros,
      gastosTotal: gastosTotal,
      fondoInicial: fondoInicial,
      fondoYape: fondoYape,
      efectivoEsperado: efectivoEsperado,
      totalRecibido: efectivo + yape,
      totalGastos: gastosTotal,
      dineroEsperado: ((efectivo + yape - gastosTotal) > 0)
          ? efectivo + yape - gastosTotal
          : 0,
      totalEsperado: ((efectivo + yape - gastosTotal) > 0)
          ? efectivo + yape - gastosTotal
          : 0,
      gastosPorCategoria: porCategoria,
      efectivoDeclarado: efectivoDeclarado,
      diferencia: diferencia,
      hayDeclaracion: hayDeclaracion,
    );
  }
}

const rendicionRepo = RendicionRepo();