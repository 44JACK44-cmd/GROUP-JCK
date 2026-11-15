/// Cola de operaciones pendientes para cuando no hay internet.
///
/// Cada operación guarda todo lo necesario para insertarse después.
/// `uuid_offline` evita duplicados si la app reintenta.
///
/// La cola es a prueba de fallos: si una operación falla, se conservan TODAS
/// las que van detrás (no se pierde ningún registro) y se reintentará más
/// tarde. Una operación ya sincronizada nunca se repite.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/caja_ingreso.dart';

class Outbox {
  static const _key = 'gasapp_outbox_v1';
  static const _uuid = Uuid();

  static SupabaseClient get _sb => Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> _leer() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final lista = <Map<String, dynamic>>[];
    for (final s in raw) {
      try {
        final m = jsonDecode(s);
        if (m is Map<String, dynamic>) lista.add(m);
      } catch (_) {
        // Operación corrupta: se ignora en vez de romper toda la cola.
      }
    }
    return lista;
  }

  static Future<void> _escribir(List<Map<String, dynamic>> ops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, ops.map((o) => jsonEncode(o)).toList());
  }

  /// Número de operaciones esperando conexión.
  static Future<int> pendientes() async => (await _leer()).length;

  /// Encola un pedido completo (cabecera + detalles).
  ///
  /// [clienteNuevo] permite registrar sin internet un pedido de un cliente que
  /// todavía no existe: al sincronizar se crea (o se reutiliza si ya está) y
  /// después se guarda el pedido. Nunca se pierde el pedido.
  static Future<void> encolarPedido({
    required Map<String, dynamic> pedido,
    required List<Map<String, dynamic>> detalles,
    Map<String, dynamic>? clienteNuevo,
  }) async {
    pedido['uuid_offline'] ??= _uuid.v4();
    final ops = await _leer();
    ops.add({
      'tipo': 'pedido',
      'uuid_offline': pedido['uuid_offline'],
      'pedido': pedido,
      'detalles': detalles,
      if (clienteNuevo != null) 'cliente_nuevo': clienteNuevo,
      'fecha': DateTime.now().toIso8601String(),
    });
    await _escribir(ops);
  }

  /// Encola una entrega completa (entrega + pago + movimientos de balón/fierro).
  static Future<void> encolarEntrega({
    required Map<String, dynamic> entrega,
    Map<String, dynamic>? pago,
    Map<String, dynamic>? movimientoBalon,
    Map<String, dynamic>? movimientoFierro,
    Map<String, dynamic>? auditoria,
  }) async {
    entrega['uuid_offline'] ??= _uuid.v4();
    if (pago != null) pago['uuid_offline'] ??= _uuid.v4();
    if (movimientoBalon != null) movimientoBalon['uuid_offline'] ??= _uuid.v4();
    if (movimientoFierro != null) movimientoFierro['uuid_offline'] ??= _uuid.v4();
    final ops = await _leer();
    ops.add({
      'tipo': 'entrega',
      'uuid_offline': entrega['uuid_offline'],
      'entrega': entrega,
      'pago': pago,
      'movimientoBalon': movimientoBalon,
      'movimientoFierro': movimientoFierro,
      'auditoria': auditoria,
      'fecha': DateTime.now().toIso8601String(),
    });
    await _escribir(ops);
  }

  /// Encola un pago suelto (abono a cuenta de una deuda).
  static Future<void> encolarPago({required Map<String, dynamic> pago}) async {
    pago['uuid_offline'] ??= _uuid.v4();
    final ops = await _leer();
    ops.add({
      'tipo': 'pago',
      'uuid_offline': pago['uuid_offline'],
      'pago': pago,
      'fecha': DateTime.now().toIso8601String(),
    });
    await _escribir(ops);
  }

  /// Encola una devolución de balón vacío.
  static Future<void> encolarDevolucion({
    required Map<String, dynamic> movimiento,
  }) async {
    movimiento['uuid_offline'] ??= _uuid.v4();
    final ops = await _leer();
    ops.add({
      'tipo': 'devolucion',
      'uuid_offline': movimiento['uuid_offline'],
      'movimiento': movimiento,
      'fecha': DateTime.now().toIso8601String(),
    });
    await _escribir(ops);
  }

  /// Reintenta todas las operaciones pendientes. Devuelve cuántas se sincronizaron.
  /// Se detiene en el primer fallo de red para no gastar batería ni datos,
  /// conservando TODAS las operaciones pendientes.
  static Future<int> procesar() async {
    final ops = await _leer();
    if (ops.isEmpty) return 0;

    var sincronizadas = 0;
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      try {
        await _ejecutar(op);
        sincronizadas++;
      } catch (_) {
        // Fallo: conservamos esta y todas las siguientes. No se pierde nada.
        break;
      }
    }

    if (sincronizadas > 0) {
      final restantes = ops.skip(sincronizadas).toList();
      await _escribir(restantes);
    }
    return sincronizadas;
  }

  static Future<void> _ejecutar(Map<String, dynamic> op) async {
    switch (op['tipo']) {
      case 'pedido':
        await _insertarPedido(op);
        break;
      case 'entrega':
        await _insertarEntrega(op);
        break;
      case 'pago':
        await _insertarPago(op);
        break;
      case 'devolucion':
        await _insertarDevolucion(op);
        break;
      default:
        // Tipo desconocido: se ignora (no se bloquea la cola).
        break;
    }
  }

  /// Inserta la cabecera y los detalles del pedido.
  /// Si la cabecera ya existe (se creó online pero el detalle falló),
  /// se recupera su id en vez de duplicar el pedido.
  static Future<void> _insertarPedido(Map<String, dynamic> op) async {
    final pedido = Map<String, dynamic>.from(op['pedido'] as Map);
    final detalles = (op['detalles'] as List).cast<Map<String, dynamic>>();
    final clienteNuevo = op['cliente_nuevo'] == null
        ? null
        : Map<String, dynamic>.from(op['cliente_nuevo'] as Map);
    final uuid = op['uuid_offline'] as String?;

    // Pedido de un cliente que se creó sin internet: primero el cliente.
    if (pedido['cliente_id'] == null && clienteNuevo != null) {
      pedido['cliente_id'] = await _clienteDelPedido(clienteNuevo, pedido);
    }

    String? pedidoId;
    if (uuid != null) {
      final existente = await _sb
          .from('pedidos')
          .select('id')
          .eq('uuid_offline', uuid)
          .maybeSingle();
      pedidoId = existente?['id'] as String?;
    }

    if (pedidoId == null) {
      final insertado = await _sb.from('pedidos').insert(pedido).select('id').single();
      pedidoId = insertado['id'] as String;
    }

    for (final d in detalles) {
      final fila = Map<String, dynamic>.from(d);
      fila['pedido_id'] = pedidoId;
      // No duplicamos la misma línea si ya se insertó.
      final yaExiste = await _sb
          .from('detalle_pedido')
          .select('id')
          .eq('pedido_id', pedidoId)
          .eq('producto_id', fila['producto_id'])
          .eq('cantidad', fila['cantidad'])
          .maybeSingle();
      if (yaExiste != null) continue;
      await _sb.from('detalle_pedido').insert(fila);
    }
  }

  /// Cliente creado sin conexión: se reutiliza si ya existe (mismo nombre y
  /// empresa) para no duplicar fichas al sincronizar varios pedidos.
  static Future<String> _clienteDelPedido(
    Map<String, dynamic> cliente,
    Map<String, dynamic> pedido,
  ) async {
    final empresaId = pedido['empresa_id'] as String;
    final nombre = (cliente['nombre'] as String? ?? '').trim();

    final existentes = await _sb
        .from('clientes')
        .select('id')
        .eq('empresa_id', empresaId)
        .eq('nombre', nombre)
        .limit(1);
    final lista = List<Map<String, dynamic>>.from(existentes as List);
    if (lista.isNotEmpty) return lista.first['id'] as String;

    final creado = await _sb
        .from('clientes')
        .insert({
          'empresa_id': empresaId,
          'nombre': nombre,
          if (cliente['telefono'] != null) 'telefono': cliente['telefono'],
          if (cliente['direccion'] != null) 'direccion': cliente['direccion'],
          if (cliente['referencia'] != null) 'referencia': cliente['referencia'],
          if (cliente['latitud'] != null) 'latitud': cliente['latitud'],
          if (cliente['longitud'] != null) 'longitud': cliente['longitud'],
          'observaciones': 'Registrado sin conexión',
        })
        .select('id')
        .single();
    return creado['id'] as String;
  }

  /// Inserta la entrega con su pago y movimientos.
  /// `entregas.pedido_id` es UNIQUE: si el pedido ya estaba entregado,
  /// la inserción se ignora (no hay doble entrega).
  static Future<void> _insertarEntrega(Map<String, dynamic> op) async {
    final entrega = Map<String, dynamic>.from(op['entrega'] as Map);
    final pago = op['pago'] == null ? null : Map<String, dynamic>.from(op['pago'] as Map);
    final balon = op['movimientoBalon'] == null
        ? null
        : Map<String, dynamic>.from(op['movimientoBalon'] as Map);
    final fierro = op['movimientoFierro'] == null
        ? null
        : Map<String, dynamic>.from(op['movimientoFierro'] as Map);
    final auditoria = op['auditoria'] == null ? null : Map<String, dynamic>.from(op['auditoria'] as Map);

    final existente = await _sb
        .from('entregas')
        .select('id')
        .eq('pedido_id', entrega['pedido_id'])
        .maybeSingle();

    if (existente == null) {
      await _sb.from('entregas').insert(entrega);
    }

    if (pago != null) {
      final yaHay = await _sb
          .from('pagos')
          .select('id')
          .eq('uuid_offline', pago['uuid_offline'])
          .maybeSingle();
      var pagoId = yaHay?['id'] as String?;
      if (pagoId == null) {
        final insertado = await _sb.from('pagos').insert(pago).select('id').single();
        pagoId = insertado['id'] as String;
      }
      await asegurarIngresoCaja(
        pagoId,
        empresaId: pago['empresa_id'] as String?,
        monto: (pago['monto'] as num?)?.toDouble(),
        usuarioId: pago['registrado_por'] as String?,
        metodo: pago['metodo'] as String?,
      );
    }

    if (balon != null) {
      final yaHay = await _sb
          .from('movimiento_bal_on')
          .select('id')
          .eq('uuid_offline', balon['uuid_offline'])
          .maybeSingle();
      if (yaHay == null) await _sb.from('movimiento_bal_on').insert(balon);
    }

    if (fierro != null) {
      final yaHay = await _sb
          .from('movimiento_fierro')
          .select('id')
          .eq('uuid_offline', fierro['uuid_offline'])
          .maybeSingle();
      if (yaHay == null) await _sb.from('movimiento_fierro').insert(fierro);
    }

    // Marcar el pedido como ENTREGADO.
    final pedidoId = entrega['pedido_id'] as String?;
    if (pedidoId != null) {
      await _sb.from('pedidos').update({'estado': 'ENTREGADO'}).eq('id', pedidoId);
    }

    if (auditoria != null) {
      try {
        await _sb.from('auditoria').insert(auditoria);
      } catch (_) {
        // La auditoría no bloquea la sincronización.
      }
    }
  }

  static Future<void> _insertarPago(Map<String, dynamic> op) async {
    final pago = Map<String, dynamic>.from(op['pago'] as Map);
    final yaHay = await _sb
        .from('pagos')
        .select('id')
        .eq('uuid_offline', pago['uuid_offline'])
        .maybeSingle();
    var pagoId = yaHay?['id'] as String?;
    if (pagoId == null) {
      final insertado = await _sb.from('pagos').insert(pago).select('id').single();
      pagoId = insertado['id'] as String;
    }
    await asegurarIngresoCaja(
      pagoId,
      empresaId: pago['empresa_id'] as String?,
      monto: (pago['monto'] as num?)?.toDouble(),
      usuarioId: pago['registrado_por'] as String?,
      metodo: pago['metodo'] as String?,
    );
  }

  static Future<void> _insertarDevolucion(Map<String, dynamic> op) async {
    final mov = Map<String, dynamic>.from(op['movimiento'] as Map);
    final yaHay = await _sb
        .from('movimiento_bal_on')
        .select('id')
        .eq('uuid_offline', mov['uuid_offline'])
        .maybeSingle();
    if (yaHay == null) await _sb.from('movimiento_bal_on').insert(mov);
  }
}
