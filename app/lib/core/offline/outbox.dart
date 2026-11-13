import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Cola de operaciones pendientes para cuando no hay internet.
/// Cada operación guarda todo lo necesario para insertarse después.
/// `uuid_offline` evita duplicados si la app reintenta.
class Outbox {
  static const _key = 'gasapp_outbox_v1';
  static const _uuid = Uuid();

  static SupabaseClient get _sb => Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> _leer() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }

  static Future<void> _escribir(List<Map<String, dynamic>> ops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, ops.map((o) => jsonEncode(o)).toList());
  }

  /// Número de operaciones esperando conexión.
  static Future<int> pendientes() async => (await _leer()).length;

  /// Encola un pedido completo (cabecera + detalles).
  static Future<void> encolarPedido({
    required Map<String, dynamic> pedido,
    required List<Map<String, dynamic>> detalles,
  }) async {
    pedido['uuid_offline'] ??= _uuid.v4();
    final ops = await _leer();
    ops.add({
      'tipo': 'pedido',
      'uuid_offline': pedido['uuid_offline'],
      'pedido': pedido,
      'detalles': detalles,
      'fecha': DateTime.now().toIso8601String(),
    });
    await _escribir(ops);
  }

  /// Encola una entrega completa (entrega + pago opcional + movimiento de balón).
  static Future<void> encolarEntrega({
    required Map<String, dynamic> entrega,
    Map<String, dynamic>? pago,
    Map<String, dynamic>? movimientoBalon,
  }) async {
    entrega['uuid_offline'] ??= _uuid.v4();
    if (pago != null) pago['uuid_offline'] ??= _uuid.v4();
    if (movimientoBalon != null) movimientoBalon['uuid_offline'] ??= _uuid.v4();
    final ops = await _leer();
    ops.add({
      'tipo': 'entrega',
      'uuid_offline': entrega['uuid_offline'],
      'entrega': entrega,
      'pago': pago,
      'movimientoBalon': movimientoBalon,
      'fecha': DateTime.now().toIso8601String(),
    });
    await _escribir(ops);
  }

  /// Reintenta todas las operaciones pendientes. Devuelve cuántas se sincronizaron.
  /// Se detiene en el primer fallo de red para no gastar batería ni datos.
  static Future<int> procesar() async {
    final ops = await _leer();
    if (ops.isEmpty) return 0;

    var sincronizadas = 0;
    final restantes = <Map<String, dynamic>>[];

    for (final op in ops) {
      try {
        if (op['tipo'] == 'pedido') {
          await _insertarPedido(op);
        } else if (op['tipo'] == 'entrega') {
          await _insertarEntrega(op);
        } else {
          restantes.add(op); // tipo desconocido: se conserva
          continue;
        }
        sincronizadas++;
      } catch (_) {
        // Error de red o de datos: conservar esta y las siguientes.
        restantes.add(op);
        restantes.addAll(ops.skipWhile((o) => !identical(o, op)).skip(1));
        break;
      }
    }

    await _escribir(restantes);
    return sincronizadas;
  }

  static Future<void> _insertarPedido(Map<String, dynamic> op) async {
    final pedido = Map<String, dynamic>.from(op['pedido'] as Map);
    final detalles = (op['detalles'] as List).cast<Map<String, dynamic>>();

    final insertado = await _sb
        .from('pedidos')
        .insert(pedido)
        .select('id')
        .single();

    final pedidoId = insertado['id'] as String;
    for (final d in detalles) {
      await _sb.from('detalle_pedido').insert({...d, 'pedido_id': pedidoId});
    }
  }

  static Future<void> _insertarEntrega(Map<String, dynamic> op) async {
    final entrega = Map<String, dynamic>.from(op['entrega'] as Map);
    final pago = op['pago'] == null
        ? null
        : Map<String, dynamic>.from(op['pago'] as Map);
    final balon = op['movimientoBalon'] == null
        ? null
        : Map<String, dynamic>.from(op['movimientoBalon'] as Map);

    await _sb.from('entregas').insert(entrega);
    if (pago != null) await _sb.from('pagos').insert(pago);
    if (balon != null) await _sb.from('movimiento_bal_on').insert(balon);

    // Marcar el pedido como ENTREGADO.
    final pedidoId = entrega['pedido_id'] as String?;
    if (pedidoId != null) {
      await _sb.from('pedidos').update({'estado': 'ENTREGADO'}).eq('id', pedidoId);
    }
  }
}
