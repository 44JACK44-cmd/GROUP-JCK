/// Control de caja.
///
/// No se duplica el sistema de caja existente: se usa `cajas` y
/// `movimiento_caja`. Los cobros de los pedidos alimentan la caja con el
/// trigger `trg_pago_ingreso_caja` (ver supabase/migration_v3.sql), de modo
/// que el dinero cobrado por los motorizados entra solo.
library;


import 'sb.dart';

/// Resumen de caja de un periodo.
class ResumenCaja {
  final double fondoInicial;
  final double ingresos;
  final double egresos;
  final double saldo;

  /// Cobros por método (de `pagos`), para el detalle que pide el admin.
  final double efectivo;
  final double yape;
  final double otros;
  final double totalCobrado;

  /// Deuda generada (ventas entregadas aún no cobradas).
  final double deudas;

  /// Gastos registrados en el periodo.
  final double gastos;

  const ResumenCaja({
    this.fondoInicial = 0,
    this.ingresos = 0,
    this.egresos = 0,
    this.saldo = 0,
    this.efectivo = 0,
    this.yape = 0,
    this.otros = 0,
    this.totalCobrado = 0,
    this.deudas = 0,
    this.gastos = 0,
  });
}

class CajaRepo {
  const CajaRepo();

  /// Caja abierta ahora (si hay).
  Future<Map<String, dynamic>?> cajaAbierta() async {
    final data = await sb
        .from('cajas')
        .select('id, fecha_apertura, fondo_inicial, estado')
        .eq('estado', 'ABIERTA')
        .order('fecha_apertura', ascending: false)
        .limit(1)
        .maybeSingle();
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  /// Movimientos de una caja.
  Future<List<Map<String, dynamic>>> movimientos(String cajaId, {int limite = 100}) async {
    final data = await sb
        .from('movimiento_caja')
        .select('id, tipo, origen, monto, descripcion, fecha, referencia_id')
        .eq('caja_id', cajaId)
        .order('fecha', ascending: false)
        .limit(limite);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> abrir({
    required String empresaId,
    required String usuarioId,
    required double fondoInicial,
  }) async {
    await sb.from('cajas').insert({
      'empresa_id': empresaId,
      'fondo_inicial': fondoInicial,
      'estado': 'ABIERTA',
    });
  }

  Future<void> cerrar({
    required String cajaId,
    required String usuarioId,
    required double montoDeclarado,
  }) async {
    await sb.from('cajas').update({
      'estado': 'CERRADA',
      'fecha_cierre': DateTime.now().toIso8601String(),
      'monto_declarado': montoDeclarado,
    }).eq('id', cajaId);
  }

  /// Ingreso manual (dinero que entra sin ser un cobro de pedido).
  Future<void> registrarIngreso({
    required String empresaId,
    required String usuarioId,
    required String cajaId,
    required double monto,
    String? descripcion,
  }) async {
    await sb.from('movimiento_caja').insert({
      'empresa_id': empresaId,
      'caja_id': cajaId,
      'tipo': 'INGRESO',
      'origen': 'MANUAL',
      'monto': monto,
      'descripcion': descripcion?.trim().isEmpty == true ? null : descripcion?.trim(),
      'usuario_id': usuarioId,
    });
  }

  /// Egreso (gasto) que también queda registrado en `gastos`.
  Future<void> registrarGasto({
    required String empresaId,
    required String usuarioId,
    required String cajaId,
    required double monto,
    required String descripcion,
    String categoria = 'GENERAL',
  }) async {
    final mov = await sb
        .from('movimiento_caja')
        .insert({
          'empresa_id': empresaId,
          'caja_id': cajaId,
          'tipo': 'EGRESO',
          'origen': 'GASTO',
          'monto': monto,
          'descripcion': descripcion.trim().isEmpty ? 'Gasto' : descripcion.trim(),
          'usuario_id': usuarioId,
        })
        .select('id')
        .single();

    await sb.from('gastos').insert({
      'empresa_id': empresaId,
      'descripcion': descripcion.trim().isEmpty ? 'Gasto' : descripcion.trim(),
      'monto': monto,
      'categoria': categoria,
      'usuario_id': usuarioId,
      'movimiento_caja_id': mov['id'],
    });
  }

  /// Resumen global del periodo (no solo de la caja abierta).
  Future<ResumenCaja> resumen({
    DateTime? desde,
    DateTime? hasta,
    Map<String, dynamic>? caja,
  }) async {
    final desdeIso = (desde ?? DateTime(2000)).toIso8601String();
    final hastaIso = (hasta ?? DateTime(2100)).toIso8601String();

    final res = await Future.wait([
      sb.from('movimiento_caja')
          .select('tipo, monto')
          .gte('fecha', desdeIso)
          .lte('fecha', hastaIso)
          .limit(5000),
      sb.from('pagos').select('monto, metodo').gte('fecha', desdeIso).lte('fecha', hastaIso).limit(5000),
      sb.from('gastos').select('monto').gte('fecha', desdeIso).lte('fecha', hastaIso).limit(5000),
      sb.from('pedidos').select('id, total').eq('estado', 'ENTREGADO').limit(5000),
    ]);

    var ingresos = 0.0, egresos = 0.0;
    for (final m in res[0] as List) {
      final monto = (m['monto'] as num? ?? 0).toDouble();
      if (m['tipo'] == 'INGRESO') {
        ingresos += monto;
      } else {
        egresos += monto;
      }
    }

    var efectivo = 0.0, yape = 0.0, otros = 0.0;
    for (final p in res[1] as List) {
      final monto = (p['monto'] as num? ?? 0).toDouble();
      switch (p['metodo'] as String? ?? 'OTRO') {
        case 'EFECTIVO':
          efectivo += monto;
          break;
        case 'YAPE':
          yape += monto;
          break;
        default:
          otros += monto;
      }
    }

    var gastos = 0.0;
    for (final g in res[2] as List) {
      gastos += (g['monto'] as num? ?? 0).toDouble();
    }

    var vendido = 0.0;
    for (final p in res[3] as List) {
      vendido += (p['total'] as num? ?? 0).toDouble();
    }

    final fondo = (caja?['fondo_inicial'] as num?)?.toDouble() ?? 0;
    final totalCobrado = efectivo + yape + otros;

    return ResumenCaja(
      fondoInicial: fondo,
      ingresos: ingresos,
      egresos: egresos,
      saldo: fondo + ingresos - egresos,
      efectivo: efectivo,
      yape: yape,
      otros: otros,
      totalCobrado: totalCobrado,
      deudas: (vendido - totalCobrado) > 0 ? vendido - totalCobrado : 0,
      gastos: gastos,
    );
  }
}

const cajaRepo = CajaRepo();
