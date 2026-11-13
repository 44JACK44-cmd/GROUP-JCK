/// Repositorio de pedidos: creación, asignación, estados y consultas.
///
/// Es la única capa que escribe en `pedidos` / `detalle_pedido`.
/// Todas las llamadas incluyen `empresa_id` para que la política RLS
/// (`empresa_id = mi_empresa()`) valide el aislamiento multi-empresa.
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/estado_pedido.dart';
import 'auditoria_repo.dart';
import 'sb.dart';

/// Una línea de producto del pedido.
class LineaPedido {
  final String productoId;
  final String nombre;
  final int cantidad;
  final double precioUnitario;

  const LineaPedido({
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.precioUnitario,
  });

  double get subtotal => cantidad * precioUnitario;

  Map<String, dynamic> aDetalle(String empresaId, String pedidoId) => {
        'empresa_id': empresaId,
        'pedido_id': pedidoId,
        'producto_id': productoId,
        'cantidad': cantidad,
        'precio_unitario': precioUnitario,
      };
}

class PedidosRepo {
  const PedidosRepo();

  // ------------------------------------------------------------------
  // Consultas
  // ------------------------------------------------------------------

  /// Lista pedidos de la empresa.
  ///
  /// - [repartidorId] filtra por motorizado asignado (obligatorio para
  ///   "Mis pedidos" del motorizado).
  /// - [estados] filtra por estado (vacío = todos).
  /// - [masAntigosPrimero] ordena por antigüedad, que es como trabaja el
  ///   reparto: primero lo que más lleva esperando.
  Future<List<Map<String, dynamic>>> listar({
    String? repartidorId,
    List<String> estados = const [],
    DateTime? desde,
    DateTime? hasta,
    int limite = 200,
    bool masAntigosPrimero = false,
  }) async {
    var q = sb.from('pedidos').select(_selectPedido);
    if (repartidorId != null) q = q.eq('repartidor_id', repartidorId);
    if (estados.isNotEmpty) q = q.inFilter('estado', estados);
    if (desde != null) q = q.gte('fecha', desde.toIso8601String());
    if (hasta != null) q = q.lte('fecha', hasta.toIso8601String());
    final data = await q.order('fecha', ascending: masAntigosPrimero).limit(limite);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Un pedido con sus datos de cliente.
  Future<Map<String, dynamic>?> obtener(String pedidoId) async {
    final data = await sb
        .from('pedidos')
        .select(_selectPedido)
        .eq('id', pedidoId)
        .maybeSingle();
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  /// Detalle de productos del pedido.
  Future<List<Map<String, dynamic>>> detalles(String pedidoId) async {
    final data = await sb
        .from('detalle_pedido')
        .select('id, cantidad, precio_unitario, producto_id, productos(nombre, capacidad_kg)')
        .eq('pedido_id', pedidoId)
        .order('id');
    return List<Map<String, dynamic>>.from(data);
  }

  /// Entrega registrada del pedido (si existe).
  Future<Map<String, dynamic>?> entregaDe(String pedidoId) async {
    final data = await sb
        .from('entregas')
        .select('id, pedido_id, estado_bal_on_vacio, estado_pago, fecha, registrado_por, uuid_offline')
        .eq('pedido_id', pedidoId)
        .maybeSingle();
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  /// Pagos registrados para un pedido.
  Future<List<Map<String, dynamic>>> pagosDe(String pedidoId) async {
    final data = await sb
        .from('pagos')
        .select('id, monto, metodo, fecha, registrado_por, cliente_id, pedido_id')
        .eq('pedido_id', pedidoId)
        .order('fecha');
    return List<Map<String, dynamic>>.from(data);
  }

  /// Conteo de pedidos (para la pantalla de inicio).
  Future<int> contar({List<String> estados = const []}) async {
    var q = sb.from('pedidos').select('id');
    if (estados.isNotEmpty) q = q.inFilter('estado', estados);
    final res = await q.count();
    return res.count;
  }

  // ------------------------------------------------------------------
  // Escritura
  // ------------------------------------------------------------------

  /// Crea un pedido con sus líneas de detalle.
  ///
  /// IMPORTANTE: las líneas se insertan con `empresa_id`. Sin eso la política
  /// RLS `detalle_admin` las rechaza y el pedido queda sin productos.
  /// Si el insert de detalles falla, se borra la cabecera para no dejar
  /// pedidos huérfanos.
  Future<String> crear({
    required String empresaId,
    required String clienteId,
    required String usuarioId,
    required List<LineaPedido> lineas,
    required double total,
    String? formaPago,
    String? observaciones,
    String? repartidorId,
    String? uuidOffline,
    String origen = 'ADMIN',
  }) async {
    if (lineas.isEmpty) {
      throw Exception('El pedido debe tener al menos un producto.');
    }
    if (total <= 0) {
      throw Exception('El pedido debe tener un precio mayor a cero.');
    }

    final uuid = uuidOffline ?? const Uuid().v4();

    final cabecera = {
      'empresa_id': empresaId,
      'cliente_id': clienteId,
      'creado_por': usuarioId,
      if (repartidorId != null) 'repartidor_id': repartidorId,
      if (formaPago != null) 'forma_pago': formaPago,
      if (observaciones != null && observaciones.isNotEmpty) 'observaciones': observaciones,
      'total': total,
      'uuid_offline': uuid,
      'origen': origen,
    };

    final insertado = await _insertarCabecera(cabecera);
    final pedidoId = insertado;

    try {
      for (final linea in lineas) {
        await sb.from('detalle_pedido').insert(linea.aDetalle(empresaId, pedidoId));
      }
    } catch (_) {
      // Rollback: no dejamos pedidos huérfanos.
      try {
        await sb.from('detalle_pedido').delete().eq('pedido_id', pedidoId);
        await sb.from('pedidos').delete().eq('id', pedidoId);
      } catch (_) {}
      rethrow;
    }

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'pedido',
      entidadId: pedidoId,
      accion: 'CREAR',
      usuarioId: usuarioId,
      detalle: {
        'total': total,
        'productos': lineas
            .map((l) => {'producto': l.nombre, 'cantidad': l.cantidad, 'precio': l.precioUnitario})
            .toList(),
        'forma_pago': formaPago,
      },
    );

    return pedidoId;
  }

  /// Inserta la cabecera del pedido.
  ///
  /// Si la base de datos todavía no admite la forma de pago "DEUDA"
  /// (migración v3 no aplicada), se reintenta sin ella para no perder el
  /// pedido: la deuda se registra igual al entregar.
  static Future<String> _insertarCabecera(Map<String, dynamic> cabecera) async {
    try {
      final res = await sb.from('pedidos').insert(cabecera).select('id').single();
      return res['id'] as String;
    } catch (e) {
      final esCheck = e is PostgrestException &&
          (e.code == '23514' ||
              e.message.toLowerCase().contains('check constraint'));
      if (esCheck && cabecera['forma_pago'] == 'DEUDA') {
        final reintento = Map<String, dynamic>.from(cabecera)..remove('forma_pago');
        final res = await sb.from('pedidos').insert(reintento).select('id').single();
        return res['id'] as String;
      }
      rethrow;
    }
  }

  /// Asigna un motorizado. `repartidorId == null` desasigna.
  Future<void> asignar({
    required String pedidoId,
    required String empresaId,
    required String usuarioId,
    String? repartidorId,
    String? nombreRepartidor,
  }) async {
    final actual = await obtener(pedidoId);
    if (actual == null) throw Exception('El pedido ya no existe.');
    final estadoActual = EstadoPedido.desdeDb(actual['estado']);
    if (!estadoActual.puedeTransicionarA(
      repartidorId == null ? EstadoPedido.nuevo : EstadoPedido.asignado,
      esAdmin: true,
    )) {
      throw Exception(estadoActual.mensajeTransicionInvalida(
        repartidorId == null ? EstadoPedido.nuevo : EstadoPedido.asignado,
      ));
    }

    await sb.from('pedidos').update({
      if (repartidorId != null) 'repartidor_id': repartidorId,
      'estado': repartidorId == null ? 'NUEVO' : 'ASIGNADO',
    }).eq('id', pedidoId);

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'pedido',
      entidadId: pedidoId,
      accion: repartidorId == null ? 'DESASIGNAR' : 'ASIGNAR',
      usuarioId: usuarioId,
      detalle: {'motorizado': nombreRepartidor ?? repartidorId},
    );
  }

  /// Cambia el estado del pedido validando la transición.
  Future<void> cambiarEstado({
    required String pedidoId,
    required String empresaId,
    required String usuarioId,
    required EstadoPedido destino,
    required bool esAdmin,
    String? motivo,
  }) async {
    final actual = await obtener(pedidoId);
    if (actual == null) throw Exception('El pedido ya no existe.');
    final estadoActual = EstadoPedido.desdeDb(actual['estado']);
    if (!estadoActual.puedeTransicionarA(destino, esAdmin: esAdmin)) {
      throw Exception(estadoActual.mensajeTransicionInvalida(destino));
    }

    await sb.from('pedidos').update({'estado': destino.db}).eq('id', pedidoId);

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'pedido',
      entidadId: pedidoId,
      accion: 'ESTADO:${destino.db}',
      usuarioId: usuarioId,
      detalle: {
        'desde': estadoActual.db,
        'hacia': destino.db,
        if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
      },
    );
  }

  /// Cancela el pedido guardando el motivo (queda en el pedido y en auditoría).
  Future<void> cancelar({
    required String pedidoId,
    required String empresaId,
    required String usuarioId,
    required String motivo,
  }) async {
    final actual = await obtener(pedidoId);
    if (actual == null) throw Exception('El pedido ya no existe.');
    final estadoActual = EstadoPedido.desdeDb(actual['estado']);
    if (!estadoActual.puedeTransicionarA(EstadoPedido.cancelado, esAdmin: true)) {
      throw Exception(estadoActual.mensajeTransicionInvalida(EstadoPedido.cancelado));
    }

    final obsActual = (actual['observaciones'] as String?)?.trim() ?? '';
    final observaciones = obsActual.isEmpty
        ? 'Cancelado: $motivo'
        : '$obsActual\nCancelado: $motivo';

    await sb.from('pedidos').update({
      'estado': 'CANCELADO',
      'observaciones': observaciones,
    }).eq('id', pedidoId);

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'pedido',
      entidadId: pedidoId,
      accion: 'CANCELAR',
      usuarioId: usuarioId,
      detalle: {'motivo': motivo},
    );
  }

  /// Reactive un pedido cancelado.
  Future<void> reactivar({
    required String pedidoId,
    required String empresaId,
    required String usuarioId,
  }) async {
    await cambiarEstado(
      pedidoId: pedidoId,
      empresaId: empresaId,
      usuarioId: usuarioId,
      destino: EstadoPedido.nuevo,
      esAdmin: true,
      motivo: 'Reactivado por el administrador',
    );
  }

  static const _selectPedido = 'id, numero, fecha, total, estado, forma_pago, observaciones, '
      'cliente_id, repartidor_id, creado_por, empresa_id, '
      'clientes(nombre, telefono, direccion, referencia, latitud, longitud)';
}

const pedidosRepo = PedidosRepo();
