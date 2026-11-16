/// Repositorio de pedidos: creación, asignación, estados y consultas.
///
/// Es la única capa que escribe en `pedidos` / `detalle_pedido`.
/// Todas las llamadas incluyen `empresa_id` para que la política RLS
/// (`empresa_id = mi_empresa()`) valide el aislamiento multi-empresa.
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/estado_pedido.dart';
import '../state/bus.dart';
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

  /// Ejecuta una consulta sobre `pedidos` incluyendo la columna `origen`.
  ///
  /// La columna llega con la migración v7. Si el servidor todavía no la tiene
  /// (error 42703) se reintenta con el conjunto base y se memoriza para no
  /// repetir el viaje fallido. Así la app funciona antes y después de migrar.
  Future<T> _conOrigen<T>(Future<T> Function(String select) ejecutar) async {
    if (!_origenDisponible) return ejecutar(_columnasBase);
    try {
      return await ejecutar(_columnasConOrigen);
    } on PostgrestException catch (e) {
      if (e.code != '42703') rethrow;
      _origenDisponible = false;
      return ejecutar(_columnasBase);
    }
  }

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
    // Intentamos traer las líneas del pedido (y su producto) para mostrar en
    // la tarjeta qué se lleva y a quién se asignó. Si el servidor no lo
    // soporta (versión antigua o migración pendiente) caemos al select base
    // sin romper la lista.
    Future<List<Map<String, dynamic>>> ejecutar(bool conDetalle) async {
      return _conOrigen(
        (select) async {
          final s = conDetalle
              ? '$select, detalle_pedido(cantidad, precio_unitario, productos(nombre, capacidad_kg, tipo))'
              : select;
          var q = sb.from('pedidos').select(s);
          if (repartidorId != null) q = q.eq('repartidor_id', repartidorId);
          if (estados.isNotEmpty) q = q.inFilter('estado', estados);
          if (desde != null) q = q.gte('fecha', desde.toIso8601String());
          if (hasta != null) q = q.lte('fecha', hasta.toIso8601String());
          final data = await q.order('fecha', ascending: masAntigosPrimero).limit(limite);
          return List<Map<String, dynamic>>.from(data);
        },
      );
    }

    try {
      return await ejecutar(true);
    } catch (_) {
      return await ejecutar(false);
    }
  }

  /// Un pedido con sus datos de cliente.
  Future<Map<String, dynamic>?> obtener(String pedidoId) async {
    final data = await _conOrigen(
      (select) => sb.from('pedidos').select(select).eq('id', pedidoId).maybeSingle(),
    );
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  /// Estado real leído de la base de datos (fuente de verdad de la UI).
  Future<String?> estadoActual(String pedidoId) async {
    final fila = await sb.from('pedidos').select('estado').eq('id', pedidoId).maybeSingle();
    return fila?['estado'] as String?;
  }

  /// Deja el pedido en ENTREGADO y **comprueba** que la base lo guardó.
  ///
  /// Sirve de cierre para cualquier flujo de entrega (detalle, tarjeta,
  /// offline). Nunca devuelve `true` si el estado real no es ENTREGADO.
  Future<bool> asegurarEntregado(String pedidoId) async {
    if (await estadoActual(pedidoId) == 'ENTREGADO') return true;

    try {
      final filas = await sb
          .from('pedidos')
          .update({'estado': 'ENTREGADO'})
          .eq('id', pedidoId)
          .select('id');
      if (List<Map<String, dynamic>>.from(filas).isEmpty) return false;
    } catch (_) {
      // Puede ser el guard de estados o RLS; se confirma leyendo.
    }

    final confirmado = await estadoActual(pedidoId) == 'ENTREGADO';
    if (confirmado) {
      SyncBus.pedidoYdinero();
    }
    return confirmado;
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
    DateTime? fecha,
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
      if (fecha != null) 'fecha': fecha.toIso8601String(),
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

    SyncBus.pedidosCambiaron();
    return pedidoId;
  }

  /// Inserta la cabecera del pedido.
  ///
  /// Tolera bases de datos sin la migración aplicada:
  /// - sin forma de pago "DEUDA" (reintenta sin ella),
  /// - sin la columna `origen` (reintenta sin ella).
  static Future<String> _insertarCabecera(Map<String, dynamic> cabecera) async {
    try {
      final res = await sb.from('pedidos').insert(cabecera).select('id').single();
      return res['id'] as String;
    } catch (e) {
      if (!esColumnaAusente(e) && !esValorInvalido(e)) rethrow;
      final reintento = Map<String, dynamic>.from(cabecera);
      var cambio = false;

      if (esColumnaAusente(e) || (esValorInvalido(e) && reintento['origen'] != null)) {
        if (reintento.remove('origen') != null) {
          cambio = true;
          _origenDisponible = false;
        }
      }
      if (esValorInvalido(e) && reintento['forma_pago'] == 'DEUDA') {
        reintento.remove('forma_pago');
        cambio = true;
      }
      if (!cambio) rethrow;

      final res = await sb.from('pedidos').insert(reintento).select('id').single();
      return res['id'] as String;
    }
  }

  /// Asigna automáticamente por zona usando la función RPC de Supabase.
  Future<String?> asignarPorZona({required String pedidoId}) async {
    try {
      final res = await sb.rpc('asignar_por_zona', params: {'p_pedido_id': pedidoId});
      return res as String?;
    } catch (_) {
      return null;
    }
  }

  /// Asigna un motorizado. `repartidorId == null` desasigna.
  ///
  /// La escritura se verifica: si la base de datos no devuelve la fila
  /// actualizada (RLS o pedido inexistente) se lanza un error visible en vez
  /// de dar por hecho una asignación que no ocurrió.
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
    final destino = repartidorId == null ? EstadoPedido.nuevo : EstadoPedido.asignado;
    // Reasignar (mismo estado ASIGNADO) es una operación administrativa
    // válida: no es una transición, es un cambio de responsable.
    if (destino != estadoActual &&
        !estadoActual.puedeTransicionarA(destino, esAdmin: true)) {
      throw Exception(estadoActual.mensajeTransicionInvalida(destino));
    }

    final filas = await sb.from('pedidos').update({
      'repartidor_id': repartidorId,
      'estado': repartidorId == null ? 'NUEVO' : 'ASIGNADO',
    }).eq('id', pedidoId).select('id');

    if (List<Map<String, dynamic>>.from(filas).isEmpty) {
      throw Exception('No se pudo actualizar el pedido: ya no existe o no tienes permiso.');
    }

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'pedido',
      entidadId: pedidoId,
      accion: repartidorId == null ? 'DESASIGNAR' : 'ASIGNAR',
      usuarioId: usuarioId,
      detalle: {'motorizado': nombreRepartidor ?? repartidorId},
    );

    SyncBus.pedidosCambiaron();
  }

  /// El motorizado toma un pedido libre (sin asignar).
  ///
  /// La validación real ocurre en el servidor (función `tomar_pedido`): rol,
  /// empresa, estado y que nadie lo haya tomado antes. Si la migración aún no
  /// está aplicada se usa la ruta directa verificando filas afectadas.
  Future<void> tomarPedido({required String pedidoId, String? nombreRepartidor}) async {
    try {
      await sb.rpc('tomar_pedido', params: {'p_pedido_id': pedidoId});
      // La función del servidor pudo no cambiar nada; se confirma leyendo.
      final estado = await estadoActual(pedidoId);
      if (estado == 'ASIGNADO' || estado == 'EN_CAMINO') {
        SyncBus.pedidosCambiaron();
        return;
      }
    } catch (e) {
      if (!esFuncionAusente(e)) rethrow;
    }

    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Tu sesión expiró. Vuelve a iniciar sesión.');

    final filas = await sb
        .from('pedidos')
        .update({'repartidor_id': uid, 'estado': 'ASIGNADO'})
        .eq('id', pedidoId)
        .eq('estado', 'NUEVO')
        .filter('repartidor_id', 'is', null)
        .select('id');

    if (List<Map<String, dynamic>>.from(filas).isEmpty) {
      throw Exception('Ese pedido ya no está disponible. Actualiza la lista.');
    }

    SyncBus.pedidosCambiaron();
  }

  /// Libera el pedido: queda sin motorizado y vuelve a `NUEVO`.
  Future<void> liberar({
    required String pedidoId,
    required String empresaId,
    required String usuarioId,
  }) async {
    try {
      await sb.rpc('liberar_pedido', params: {'p_pedido_id': pedidoId});
    } catch (e) {
      if (!esFuncionAusente(e)) rethrow;
      await asignar(
        pedidoId: pedidoId,
        empresaId: empresaId,
        usuarioId: usuarioId,
      );
      return;
    }

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'pedido',
      entidadId: pedidoId,
      accion: 'DESASIGNAR',
      usuarioId: usuarioId,
      detalle: const {'motorizado': null},
    );

    SyncBus.pedidosCambiaron();
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

    final filas = await sb
        .from('pedidos')
        .update({'estado': destino.db})
        .eq('id', pedidoId)
        .select('id');

    if (List<Map<String, dynamic>>.from(filas).isEmpty) {
      throw Exception('No se pudo cambiar el estado: ya no existe o no tienes permiso.');
    }

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

    SyncBus.pedidoYdinero();
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

    final filas = await sb.from('pedidos').update({
      'estado': 'CANCELADO',
      'observaciones': observaciones,
    }).eq('id', pedidoId).select('id');

    if (List<Map<String, dynamic>>.from(filas).isEmpty) {
      throw Exception('No se pudo cancelar: ya no existe o no tienes permiso.');
    }

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'pedido',
      entidadId: pedidoId,
      accion: 'CANCELAR',
      usuarioId: usuarioId,
      detalle: {'motivo': motivo},
    );

    SyncBus.pedidosCambiaron();
  }

  /// Reactiva un pedido cerrado (entregado, cancelado o no entregado).
  ///
  /// Lo hace la función `reactivar_pedido` en el servidor: valida rol ADMIN,
  /// empresa y estado, y deja rastro en auditoría.
  Future<void> reactivar({
    required String pedidoId,
    required String empresaId,
    required String usuarioId,
  }) async {
    try {
      await sb.rpc('reactivar_pedido', params: {
        'p_pedido_id': pedidoId,
        'p_motivo': 'Reactivado por el administrador',
      });
      // Confirmar que el pedido salió del estado cerrado.
      final estado = await estadoActual(pedidoId);
      if (estado != 'ENTREGADO' && estado != 'CANCELADO') {
        SyncBus.pedidoYdinero();
      }
      return;
    } catch (e) {
      if (!esFuncionAusente(e)) rethrow;
    }

    // Respaldo para bases de datos sin la migración aplicada.
    final filas = await sb.from('pedidos').update({
      'estado': 'NUEVO',
      'repartidor_id': null,
    }).eq('id', pedidoId).select('id');

    if (List<Map<String, dynamic>>.from(filas).isEmpty) {
      throw Exception('No se pudo reactivar el pedido: ya no existe o no tienes permiso.');
    }

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'pedido',
      entidadId: pedidoId,
      accion: 'REACTIVAR',
      usuarioId: usuarioId,
      detalle: const {'motivo': 'Reactivado por el administrador'},
    );

    SyncBus.pedidoYdinero();
  }

  /// ¿El servidor ya tiene `pedidos.origen`? (migración v7)
  static bool _origenDisponible = true;

  static const _columnasBase =
      'id, numero, fecha, total, estado, forma_pago, observaciones, '
      'cliente_id, repartidor_id, creado_por, empresa_id, '
      'clientes(nombre, telefono, direccion, referencia, latitud, longitud)';

  static const _columnasConOrigen =
      'id, numero, fecha, total, estado, forma_pago, origen, observaciones, '
      'cliente_id, repartidor_id, creado_por, empresa_id, '
      'clientes(nombre, telefono, direccion, referencia, latitud, longitud)';
}

const pedidosRepo = PedidosRepo();
