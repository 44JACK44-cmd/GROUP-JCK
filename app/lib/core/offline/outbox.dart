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
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/caja_ingreso.dart';
import '../state/bus.dart';

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

  /// Encola un pedido ya entregado por el motorizado (Mi registro).
  ///
  /// Al sincronizar crea cliente + pedido + entrega + pago + balón en una sola
  /// operación, de forma idempotente. No duplica movimientos si se reintenta.
  static Future<void> encolarPedidoCompleto({
    required String uuidOffline,
    required Map<String, dynamic> pedido,
    Map<String, dynamic>? clienteNuevo,
    required List<Map<String, dynamic>> detalles,
    required Map<String, dynamic> entrega,
    Map<String, dynamic>? pago,
    Map<String, dynamic>? balon,
    String? comprobanteLocalPath,
  }) async {
    pedido['uuid_offline'] ??= uuidOffline;
    final ops = await _leer();
    ops.add({
      'tipo': 'pedido_completo',
      'uuid_offline': uuidOffline,
      'pedido': pedido,
      'cliente_nuevo': clienteNuevo,
      'detalles': detalles,
      'entrega': entrega,
      'pago': pago,
      'balon': balon,
      'comprobante_local_path': comprobanteLocalPath,
      'fecha': DateTime.now().toIso8601String(),
    });
    await _escribir(ops);
  }

  /// Encola una entrega completa (entrega + pago + movimientos de balón/fierro).
  ///
  /// [comprobanteLocalPath] conserva la foto de Yape hasta que se pueda subir.
  /// [balonDevuelto]/[fierroDevuelto] registran la devolución del vacío.
  static Future<void> encolarEntrega({
    required Map<String, dynamic> entrega,
    Map<String, dynamic>? pago,
    Map<String, dynamic>? movimientoBalon,
    Map<String, dynamic>? movimientoFierro,
    Map<String, dynamic>? auditoria,
    String? comprobanteLocalPath,
    String? clienteId,
    bool balonDevuelto = false,
    bool fierroDevuelto = false,
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
      'comprobante_local_path': comprobanteLocalPath,
      'cliente_id': clienteId ?? pago?['cliente_id'] as String?,
      'balon_devuelto': balonDevuelto,
      'fierro_devuelto': fierroDevuelto,
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

  /// Encola un gasto registrado sin conexión (Mi registro).
  static Future<void> encolarGasto({required Map<String, dynamic> gasto}) async {
    gasto['uuid_offline'] ??= _uuid.v4();
    final ops = await _leer();
    ops.add({
      'tipo': 'gasto',
      'uuid_offline': gasto['uuid_offline'],
      'gasto': gasto,
      'fecha': DateTime.now().toIso8601String(),
    });
    await _escribir(ops);
  }

  /// Encola una incidencia registrada sin conexión.
  static Future<void> encolarIncidencia({
    required Map<String, dynamic> incidencia,
  }) async {
    incidencia['uuid_offline'] ??= _uuid.v4();
    final ops = await _leer();
    ops.add({
      'tipo': 'incidencia',
      'uuid_offline': incidencia['uuid_offline'],
      'incidencia': incidencia,
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
      // Todo lo que se acaba de subir ya es dato real: avisar a las pantallas.
      SyncBus.pedidoYdinero();
    }
    return sincronizadas;
  }

  static Future<void> _ejecutar(Map<String, dynamic> op) async {
    switch (op['tipo']) {
      case 'pedido':
        await _insertarPedido(op);
        break;
      case 'pedido_completo':
        await _insertarPedidoCompleto(op);
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
      case 'gasto':
        await _insertarGasto(op);
        break;
      case 'incidencia':
        await _insertarIncidencia(op);
        break;
      default:
        // Tipo desconocido: se ignora (no se bloquea la cola).
        break;
    }
  }

  /// Inserta un pedido ya entregado por el motorizado (Mi registro).
  static Future<void> _insertarPedidoCompleto(Map<String, dynamic> op) async {
    final pedido = Map<String, dynamic>.from(op['pedido'] as Map);
    final detalles = (op['detalles'] as List).cast<Map<String, dynamic>>();
    final clienteNuevo = op['cliente_nuevo'] == null
        ? null
        : Map<String, dynamic>.from(op['cliente_nuevo'] as Map);
    final entrega = Map<String, dynamic>.from(op['entrega'] as Map);
    final pago = op['pago'] == null ? null : Map<String, dynamic>.from(op['pago'] as Map);
    final balon = op['balon'] == null ? null : Map<String, dynamic>.from(op['balon'] as Map);
    final comprobanteLocalPath = op['comprobante_local_path'] as String? ??
        (pago?['comprobante_local_path'] as String?);
    final uuid = op['uuid_offline'] as String?;

    // 1) Cliente.
    String? clienteId = pedido['cliente_id'] as String?;
    if (clienteId == null && clienteNuevo != null) {
      final empresaId = pedido['empresa_id'] as String;
      final nombre = (clienteNuevo['nombre'] as String? ?? '').trim();
      final existentes = await _sb
          .from('clientes')
          .select('id')
          .eq('empresa_id', empresaId)
          .eq('nombre', nombre)
          .limit(1);
      final lista = List<Map<String, dynamic>>.from(existentes as List);
      if (lista.isNotEmpty) {
        clienteId = lista.first['id'] as String;
      } else {
        final creado = await _sb
            .from('clientes')
            .insert({
              'empresa_id': empresaId,
              'nombre': nombre,
              if (clienteNuevo['telefono'] != null) 'telefono': clienteNuevo['telefono'],
              if (clienteNuevo['direccion'] != null) 'direccion': clienteNuevo['direccion'],
              if (clienteNuevo['referencia'] != null) 'referencia': clienteNuevo['referencia'],
              if (clienteNuevo['latitud'] != null) 'latitud': clienteNuevo['latitud'],
              if (clienteNuevo['longitud'] != null) 'longitud': clienteNuevo['longitud'],
            })
            .select('id')
            .single();
        clienteId = creado['id'] as String;
      }
    }
    if (clienteId != null) {
      pedido['cliente_id'] = clienteId;
      entrega['cliente_id'] = clienteId;
      if (pago != null) pago['cliente_id'] = clienteId;
      if (balon != null) balon['cliente_id'] = clienteId;
    }

    // 2) Pedido (idempotente por uuid_offline).
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
      final insertado = await _sb
          .from('pedidos')
          .insert({...pedido, 'estado': 'ENTREGADO'})
          .select('id')
          .single();
      pedidoId = insertado['id'] as String;
    }

    // 3) Detalles.
    for (final d in detalles) {
      final fila = Map<String, dynamic>.from(d);
      fila['pedido_id'] = pedidoId;
      final yaExiste = await _sb
          .from('detalle_pedido')
          .select('id')
          .eq('pedido_id', pedidoId)
          .eq('producto_id', fila['producto_id'])
          .maybeSingle();
      if (yaExiste != null) continue;
      try {
        await _sb.from('detalle_pedido').insert(fila);
      } catch (_) {}
    }

    // 4) Entrega (idempotente: pedido_id es UNIQUE).
    final entregaExistente = await _sb
        .from('entregas')
        .select('id')
        .eq('pedido_id', pedidoId)
        .maybeSingle();
    if (entregaExistente == null) {
      final entregaRow = Map<String, dynamic>.from(entrega);
      entregaRow['pedido_id'] = pedidoId;
      entregaRow['uuid_offline'] ??= _uuid.v4();
      try {
        await _sb.from('entregas').insert(entregaRow);
      } catch (_) {}
    }

    // 5) Pago (idempotente por uuid_offline del pago).
    if (pago != null && clienteId != null) {
      final monto = (pago['monto'] as num? ?? 0).toDouble();
      if (monto > 0.009) {
        // Subir comprobante si hay foto local.
        String? comprobanteUrl;
        if (comprobanteLocalPath != null) {
          comprobanteUrl = await _subirComprobante(comprobanteLocalPath);
        }
        final pagoRow = _limpiarPago(pago);
        pagoRow['pedido_id'] = pedidoId;
        pagoRow['cliente_id'] = clienteId;
        pagoRow['uuid_offline'] ??= _uuid.v4();
        if (comprobanteUrl != null) pagoRow['comprobante_url'] = comprobanteUrl;
        // Evitar duplicado por uuid_offline.
        final yaPago = await _sb
            .from('pagos')
            .select('id')
            .eq('uuid_offline', pagoRow['uuid_offline'])
            .maybeSingle();
        if (yaPago == null) {
          await _insertarPagoConRespaldo(pagoRow);
        }
      }
    }

    // 6) Balón.
    if (balon != null && clienteId != null) {
      final cantidad = (balon['cantidad'] as num? ?? 0).toInt();
      if (cantidad > 0) {
        final balonRow = Map<String, dynamic>.from(balon);
        balonRow['pedido_id'] = pedidoId;
        balonRow['cliente_id'] = clienteId;
        balonRow['tipo'] = 'ENTREGA_LLENO';
        balonRow['uuid_offline'] ??= _uuid.v4();
        final yaBalon = await _sb
            .from('movimiento_bal_on')
            .select('id')
            .eq('pedido_id', pedidoId)
            .eq('tipo', 'ENTREGA_LLENO')
            .maybeSingle();
        if (yaBalon == null) {
          try {
            await _sb.from('movimiento_bal_on').insert(balonRow);
          } catch (_) {}
        }
      }
    }
  }

  static Future<String?> _subirComprobante(String localPath) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) return null;
      final ext = localPath.split('.').last.toLowerCase();
      final name = '${_uuid.v4()}.$ext';
      final path = 'yape/$name';
      final bytes = await file.readAsBytes();
      final ct = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
      await _sb.storage
          .from('comprobantes')
          .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: ct));
      return _sb.storage.from('comprobantes').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  /// Quita del pago las claves que no son columnas de `pagos`.
  ///
  /// El bug original: `pedido_completo` metía `comprobante_local_path` dentro
  /// del mapa del pago. PostgREST rechazaba la fila entera y el cobro se
  /// perdía en silencio. Ahora se limpia antes de insertar.
  static Map<String, dynamic> _limpiarPago(Map source) {
    final fila = Map<String, dynamic>.from(source);
    fila.remove('comprobante_local_path');
    return fila;
  }

  /// Inserta el pago y devuelve la fila. Si la base todavía no tiene
  /// `pagos.comprobante_url` (migración pendiente), reintenta sin la columna
  /// para no perder el cobro.
  static Future<Map<String, dynamic>> _insertarPagoConRespaldo(
    Map<String, dynamic> pagoRow,
  ) async {
    try {
      return await _sb.from('pagos').insert(pagoRow).select('id').single();
    } catch (e) {
      if (pagoRow.containsKey('comprobante_url')) {
        final sinFoto = Map<String, dynamic>.from(pagoRow)..remove('comprobante_url');
        try {
          return await _sb.from('pagos').insert(sinFoto).select('id').single();
        } catch (_) {}
      }
      rethrow;
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
    final comprobanteLocalPath = op['comprobante_local_path'] as String?;
    final clienteId = (op['cliente_id'] as String?) ?? pago?['cliente_id'] as String?;
    final balonDevuelto = op['balon_devuelto'] as bool? ?? false;
    final fierroDevuelto = op['fierro_devuelto'] as bool? ?? false;
    final pedidoId = entrega['pedido_id'] as String?;

    final existente = await _sb
        .from('entregas')
        .select('id')
        .eq('pedido_id', entrega['pedido_id'])
        .maybeSingle();

    if (existente == null) {
      await _sb.from('entregas').insert(entrega);
    }

    if (pago != null) {
      final pagoRow = _limpiarPago(pago);
      final yaHay = await _sb
          .from('pagos')
          .select('id')
          .eq('uuid_offline', pagoRow['uuid_offline'])
          .maybeSingle();
      var pagoId = yaHay?['id'] as String?;
      if (pagoId == null) {
        // Subir la foto antes del cobro: si falla la subida se reintenta la
        // operación completa y no se pierde el comprobante.
        if (comprobanteLocalPath != null) {
          final url = await _subirComprobante(comprobanteLocalPath);
          if (url != null) pagoRow['comprobante_url'] = url;
        }
        final insertado =
            await _insertarPagoConRespaldo(pagoRow);
        pagoId = insertado['id'] as String;
      }
      await asegurarIngresoCaja(
        pagoId,
        empresaId: pagoRow['empresa_id'] as String?,
        monto: (pagoRow['monto'] as num?)?.toDouble(),
        usuarioId: pagoRow['registrado_por'] as String?,
        metodo: pagoRow['metodo'] as String?,
      );
    }

    if (balon != null) {
      final yaHay = await _sb
          .from('movimiento_bal_on')
          .select('id')
          .eq('uuid_offline', balon['uuid_offline'])
          .maybeSingle();
      if (yaHay == null) await _sb.from('movimiento_bal_on').insert(balon);

      // El vacío devuelto es información logística del mismo pedido.
      if (balonDevuelto && clienteId != null && pedidoId != null) {
        final yaDevuelto = await _sb
            .from('movimiento_bal_on')
            .select('id')
            .eq('pedido_id', pedidoId)
            .eq('tipo', 'DEVOLUCION_VACIO')
            .maybeSingle();
        if (yaDevuelto == null) {
          await _sb.from('movimiento_bal_on').insert({
            'empresa_id': balon['empresa_id'],
            'cliente_id': clienteId,
            'tipo': 'DEVOLUCION_VACIO',
            'pedido_id': pedidoId,
            'cantidad': balon['cantidad'],
            'usuario_id': balon['usuario_id'],
            'uuid_offline': _uuid.v4(),
          });
        }
      }
    }

    if (fierro != null) {
      final yaHay = await _sb
          .from('movimiento_fierro')
          .select('id')
          .eq('uuid_offline', fierro['uuid_offline'])
          .maybeSingle();
      if (yaHay == null) await _sb.from('movimiento_fierro').insert(fierro);

      if (fierroDevuelto && clienteId != null && pedidoId != null) {
        final yaDevuelto = await _sb
            .from('movimiento_fierro')
            .select('id')
            .eq('pedido_id', pedidoId)
            .eq('tipo', 'DEVOLUCION')
            .maybeSingle();
        if (yaDevuelto == null) {
          await _sb.from('movimiento_fierro').insert({
            'empresa_id': fierro['empresa_id'],
            'cliente_id': clienteId,
            'tipo': 'DEVOLUCION',
            'pedido_id': pedidoId,
            'cantidad': fierro['cantidad'],
            'usuario_id': fierro['usuario_id'],
            'uuid_offline': _uuid.v4(),
          });
        }
      }
    }

    // Marcar el pedido como ENTREGADO.
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
    final pago = _limpiarPago(op['pago'] as Map);
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

  static Future<void> _insertarGasto(Map<String, dynamic> op) async {
    final gasto = Map<String, dynamic>.from(op['gasto'] as Map);
    final uuid = gasto['uuid_offline'] as String?;
    // Idempotencia: si la base ya tiene `uuid_offline`, se comprueba; si la
    // migración aún no está, se evita duplicar por descripción+monto+fecha.
    if (uuid != null) {
      try {
        final ya = await _sb
            .from('gastos')
            .select('id')
            .eq('uuid_offline', uuid)
            .maybeSingle();
        if (ya != null) return;
      } catch (_) {
        final ya = await _sb
            .from('gastos')
            .select('id')
            .eq('descripcion', gasto['descripcion'] as String? ?? '')
            .eq('monto', gasto['monto'])
            .eq('fecha', gasto['fecha'])
            .maybeSingle();
        if (ya != null) return;
      }
    }
    try {
      await _sb.from('gastos').insert(gasto);
    } catch (_) {
      if (!gasto.containsKey('uuid_offline')) rethrow;
      final sinUuid = Map<String, dynamic>.from(gasto)..remove('uuid_offline');
      await _sb.from('gastos').insert(sinUuid);
    }
  }

  static Future<void> _insertarIncidencia(Map<String, dynamic> op) async {
    final inc = Map<String, dynamic>.from(op['incidencia'] as Map);
    final ya = await _sb
        .from('incidencias')
        .select('id')
        .eq('uuid_offline', inc['uuid_offline'])
        .maybeSingle();
    if (ya == null) await _sb.from('incidencias').insert(inc);
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
