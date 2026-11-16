/// Consultas de actividad para el admin y el motorizado.
///
/// Todo sale de las tablas reales (`pedidos`, `pagos`, `gastos`,
/// `incidencias`). No hay datos de ejemplo ni cálculos paralelos: la UI solo
/// pinta lo que devuelve este repositorio.
library;

import 'dart:math' as math;

import '../domain/formato.dart';
import 'sb.dart';

/// Un movimiento real de la jornada (pedido, cobro, gasto, incidencia).
class MovimientoActividad {
  final DateTime fecha;
  final String tipo; // PEDIDO | PAGO | GASTO | INCIDENCIA | BALON
  final String titulo;
  final String detalle;
  final double monto;
  final String? metodo;
  final String estado;
  final String? pedidoId;
  final String? comprobanteUrl;

  const MovimientoActividad({
    required this.fecha,
    required this.tipo,
    required this.titulo,
    required this.detalle,
    this.monto = 0,
    this.metodo,
    this.estado = '',
    this.pedidoId,
    this.comprobanteUrl,
  });
}

/// Resumen "en vivo" de un motorizado para la pantalla principal del admin.
class ResumenVivo {
  final int pedidos;
  final int entregados;
  final double ventas;
  final DateTime? ultimaActividad;
  final String ultimoMovimiento;

  const ResumenVivo({
    this.pedidos = 0,
    this.entregados = 0,
    this.ventas = 0,
    this.ultimaActividad,
    this.ultimoMovimiento = '',
  });

  bool get sinActividad => ultimaActividad == null;
}

class ActividadRepo {
  const ActividadRepo();

  /// Gastos de un usuario en un rango. Si la base todavía no tiene
  /// `medio_pago`, se reintenta sin esa columna para no romper la pantalla.
  Future<List<Map<String, dynamic>>> gastosDe({
    required String usuarioId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    Future<List<Map<String, dynamic>>> consultar(String cols) => sb
        .from('gastos')
        .select(cols)
        .eq('usuario_id', usuarioId)
        .gte('fecha', desde.toIso8601String())
        .lte('fecha', hasta.toIso8601String())
        .order('fecha', ascending: false)
        .limit(200)
        .then((v) => List<Map<String, dynamic>>.from(v as List));

    try {
      return await consultar(
        'id, descripcion, monto, categoria, fecha, medio_pago, comprobante_url',
      );
    } catch (_) {
      try {
        return await consultar('id, descripcion, monto, categoria, fecha');
      } catch (_) {
        return [];
      }
    }
  }

  /// Incidencias de un usuario en un rango.
  Future<List<Map<String, dynamic>>> incidenciasDe({
    required String usuarioId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    try {
      final data = await sb
          .from('incidencias')
          .select('id, tipo, descripcion, monto, fecha, comprobante_url')
          .eq('usuario_id', usuarioId)
          .gte('fecha', desde.toIso8601String())
          .lte('fecha', hasta.toIso8601String())
          .order('fecha', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  /// Comprobantes (fotos de Yape) de una lista de pedidos.
  ///
  /// Devuelve `pedidoId → url`. Si la migración `pagos.comprobante_url`
  /// todavía no está aplicada, devuelve un mapa vacío sin romper nada.
  Future<Map<String, String>> comprobantesDePedidos(List<String> pedidoIds) async {
    if (pedidoIds.isEmpty) return {};
    try {
      final data = await sb
          .from('pagos')
          .select('pedido_id, comprobante_url, metodo, monto, fecha')
          .inFilter('pedido_id', pedidoIds)
          .order('fecha');
      final mapa = <String, String>{};
      for (final p in data) {
        final id = p['pedido_id'] as String?;
        final url = p['comprobante_url'] as String?;
        if (id != null && url != null && url.isNotEmpty) {
          mapa[id] = url;
        }
      }
      return mapa;
    } catch (_) {
      return {};
    }
  }

  /// Pagos de una lista de pedidos (para mostrar Yape/efectivo aunque la
  /// entrega se haya hecho desde el detalle y no desde "Mi registro").
  Future<Map<String, List<Map<String, dynamic>>>> pagosDePedidos(
    List<String> pedidoIds,
  ) async {
    if (pedidoIds.isEmpty) return {};
    try {
      final data = await sb
          .from('pagos')
          .select('pedido_id, monto, metodo, fecha')
          .inFilter('pedido_id', pedidoIds)
          .order('fecha');
      final mapa = <String, List<Map<String, dynamic>>>{};
      for (final p in data) {
        final id = p['pedido_id'] as String?;
        if (id == null) continue;
        mapa.putIfAbsent(id, () => []).add(Map<String, dynamic>.from(p));
      }
      return mapa;
    } catch (_) {
      return {};
    }
  }

  /// Resumen de hoy por motorizado, en dos consultas (pedidos + gastos).
  ///
  /// Se usa en el bloque "Actividad en vivo" del inicio del admin. La última
  /// actividad se calcula con la fecha real del último pedido o gasto.
  Future<Map<String, ResumenVivo>> resumenVivoHoy() async {
    final inicio = inicioHoy();
    final fin = DateTime.now().add(const Duration(minutes: 1));
    try {
      final res = await Future.wait([
        sb
            .from('pedidos')
            .select('id, estado, total, fecha, repartidor_id, clientes(nombre)')
            .gte('fecha', inicio.toIso8601String())
            .lte('fecha', fin.toIso8601String())
            .order('fecha', ascending: false)
            .limit(2000),
        sb
            .from('gastos')
            .select('usuario_id, monto, descripcion, fecha')
            .gte('fecha', inicio.toIso8601String())
            .lte('fecha', fin.toIso8601String())
            .order('fecha', ascending: false)
            .limit(1000),
      ]);

      final pedidos = List<Map<String, dynamic>>.from(res[0] as List);
      final gastos = List<Map<String, dynamic>>.from(res[1] as List);

      final acumulado = <String, _Acumulado>{};
      for (final p in pedidos) {
        final uid = p['repartidor_id'] as String?;
        if (uid == null) continue;
        final a = acumulado.putIfAbsent(uid, _Acumulado.new);
        a.pedidos++;
        final estado = p['estado'] as String? ?? '';
        if (estado == 'ENTREGADO') {
          a.entregados++;
          a.ventas += (p['total'] as num? ?? 0).toDouble();
        }
        final fecha = parseFecha(p['fecha']);
        if (fecha != null) {
          a.registrar(fecha, _textoPedido(estado, p));
        }
      }
      for (final g in gastos) {
        final uid = g['usuario_id'] as String?;
        if (uid == null) continue;
        final a = acumulado.putIfAbsent(uid, _Acumulado.new);
        final fecha = parseFecha(g['fecha']);
        if (fecha != null) {
          a.registrar(
            fecha,
            'Gasto: ${g['descripcion'] ?? 'gasto'} · ${dinero((g['monto'] as num? ?? 0).toDouble())}',
          );
        }
      }

      return {
        for (final e in acumulado.entries)
          e.key: ResumenVivo(
            pedidos: e.value.pedidos,
            entregados: e.value.entregados,
            ventas: e.value.ventas,
            ultimaActividad: e.value.ultima,
            ultimoMovimiento: e.value.ultimoTexto,
          ),
      };
    } catch (_) {
      return {};
    }
  }

  /// Línea de tiempo de TODA la empresa (solo ADMIN por RLS).
  /// Reutiliza las mismas tablas: pedidos, pagos, gastos e incidencias.
  Future<List<MovimientoActividad>> movimientosDeTodos({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final res = await Future.wait([
      sb
          .from('pedidos')
          .select(
            'id, numero, fecha, total, estado, forma_pago, origen, '
            'clientes(nombre)',
          )
          .gte('fecha', desde.toIso8601String())
          .lte('fecha', hasta.toIso8601String())
          .order('fecha', ascending: false)
          .limit(400),
      sb
          .from('gastos')
          .select('descripcion, monto, categoria, fecha, medio_pago')
          .gte('fecha', desde.toIso8601String())
          .lte('fecha', hasta.toIso8601String())
          .order('fecha', ascending: false)
          .limit(400),
      sb
          .from('incidencias')
          .select('tipo, descripcion, monto, fecha')
          .gte('fecha', desde.toIso8601String())
          .lte('fecha', hasta.toIso8601String())
          .order('fecha', ascending: false)
          .limit(400),
    ]);

    final items = <MovimientoActividad>[];
    for (final p in res[0] as List) {
      final pedido = p as Map<String, dynamic>;
      final cliente =
          (pedido['clientes'] as Map?)?['nombre'] as String? ?? 'Cliente';
      final estado = pedido['estado'] as String? ?? '';
      items.add(MovimientoActividad(
        fecha: parseFecha(pedido['fecha']) ?? DateTime.now(),
        tipo: 'PEDIDO',
        titulo: estado == 'ENTREGADO'
            ? 'Pedido entregado a $cliente'
            : 'Pedido #${pedido['numero'] ?? ''} · $cliente',
        detalle: pedido['origen'] == 'MOTORIZADO'
            ? 'Registrado por motorizado'
            : 'Pedido de recepción',
        monto: (pedido['total'] as num? ?? 0).toDouble(),
        estado: estado,
        metodo: pedido['forma_pago'] as String?,
      ));
    }
    for (final g in res[1] as List) {
      final gasto = g as Map<String, dynamic>;
      items.add(MovimientoActividad(
        fecha: parseFecha(gasto['fecha']) ?? DateTime.now(),
        tipo: 'GASTO',
        titulo: 'Gasto: ${gasto['categoria'] ?? 'gasto'}',
        detalle: gasto['descripcion'] as String? ?? '',
        monto: (gasto['monto'] as num? ?? 0).toDouble(),
        metodo: gasto['medio_pago'] as String?,
      ));
    }
    for (final i in res[2] as List) {
      final inc = i as Map<String, dynamic>;
      items.add(MovimientoActividad(
        fecha: parseFecha(inc['fecha']) ?? DateTime.now(),
        tipo: 'INCIDENCIA',
        titulo: 'Falla: ${inc['tipo'] ?? ''}',
        detalle: inc['descripcion'] as String? ?? '',
        monto: (inc['monto'] as num? ?? 0).toDouble(),
      ));
    }
    items.sort((a, b) => b.fecha.compareTo(a.fecha));
    return items;
  }

  String _textoPedido(String estado, Map<String, dynamic> p) {
    final cliente = (p['clientes'] as Map?)?['nombre'] as String? ?? 'Cliente';
    final monto = dinero((p['total'] as num? ?? 0).toDouble());
    if (estado == 'ENTREGADO') return 'Entregó a $cliente · $monto';
    if (estado == 'EN_CAMINO') return 'En camino a $cliente';
    if (estado == 'CANCELADO') return 'Pedido cancelado · $cliente';
    return 'Pedido de $cliente · $monto';
  }

  /// Mezcla pedidos, gastos e incidencias de un motorizado en una sola línea
  /// de tiempo. Es la misma información que ve el motorizado en "Mi registro".
  Future<List<MovimientoActividad>> movimientosDe({
    required String motorizadoId,
    required DateTime desde,
    required DateTime hasta,
    List<Map<String, dynamic>>? pedidos,
  }) async {
    final res = await Future.wait([
      gastosDe(usuarioId: motorizadoId, desde: desde, hasta: hasta),
      incidenciasDe(usuarioId: motorizadoId, desde: desde, hasta: hasta),
    ]);

    final List<Map<String, dynamic>> listaPedidos;
    if (pedidos != null) {
      listaPedidos = pedidos;
    } else {
      final data = await sb
          .from('pedidos')
          .select('id, numero, fecha, total, estado, forma_pago, origen, repartidor_id, clientes(nombre)')
          .eq('repartidor_id', motorizadoId)
          .gte('fecha', desde.toIso8601String())
          .lte('fecha', hasta.toIso8601String())
          .order('fecha', ascending: false)
          .limit(300);
      listaPedidos = List<Map<String, dynamic>>.from(data as List);
    }

    final ids = listaPedidos.map((p) => p['id'] as String).toList();
    final comprobantes = await comprobantesDePedidos(ids);

    final items = <MovimientoActividad>[];
    for (final p in listaPedidos) {
      final cliente = (p['clientes'] as Map?)?['nombre'] as String? ?? 'Cliente';
      final estado = p['estado'] as String? ?? '';
      final total = (p['total'] as num? ?? 0).toDouble();
      items.add(MovimientoActividad(
        fecha: parseFecha(p['fecha']) ?? DateTime.now(),
        tipo: 'PEDIDO',
        titulo: cliente,
        detalle: 'Pedido #${p['numero'] ?? ''}',
        monto: total,
        estado: estado,
        metodo: p['forma_pago'] as String?,
        pedidoId: p['id'] as String?,
        comprobanteUrl: comprobantes[p['id']],
      ));
    }
    for (final g in res[0]) {
      items.add(MovimientoActividad(
        fecha: parseFecha(g['fecha']) ?? DateTime.now(),
        tipo: 'GASTO',
        titulo: 'Gasto: ${g['categoria'] ?? 'gasto'}',
        detalle: g['descripcion'] as String? ?? '',
        monto: (g['monto'] as num? ?? 0).toDouble(),
        metodo: g['medio_pago'] as String?,
        comprobanteUrl: g['comprobante_url'] as String?,
      ));
    }
    for (final i in res[1]) {
      items.add(MovimientoActividad(
        fecha: parseFecha(i['fecha']) ?? DateTime.now(),
        tipo: 'INCIDENCIA',
        titulo: 'Incidencia: ${i['tipo'] ?? ''}',
        detalle: i['descripcion'] as String? ?? '',
        monto: (i['monto'] as num? ?? 0).toDouble(),
        comprobanteUrl: i['comprobante_url'] as String?,
      ));
    }

    items.sort((a, b) => b.fecha.compareTo(a.fecha));
    return items;
  }

  /// Primera línea de un movimiento (para el bloque en vivo).
  static String resumenCorto(ResumenVivo r) {
    if (r.sinActividad) return 'Sin actividad';
    final minutos = math.max(0, DateTime.now().difference(r.ultimaActividad!).inMinutes);
    final hace = minutos < 1
        ? 'ahora'
        : minutos < 60
            ? 'hace $minutos min'
            : 'hace ${(minutos / 60).floor()} h';
    return '${r.ultimoMovimiento} · $hace';
  }
}

class _Acumulado {
  int pedidos = 0;
  int entregados = 0;
  double ventas = 0;
  DateTime? ultima;
  String ultimoTexto = '';

  void registrar(DateTime fecha, String texto) {
    if (ultima == null || fecha.isAfter(ultima!)) {
      ultima = fecha;
      ultimoTexto = texto;
    }
  }
}

const actividadRepo = ActividadRepo();
