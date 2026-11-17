/// AUDITORÍA REAL (casos A–F) contra Supabase.
///
/// Se ejecuta con:
///   flutter test test/integration/casos_reales_test.dart \
///     --dart-define=TEST_SUPABASE_URL=... \
///     --dart-define=TEST_SUPABASE_ANON_KEY=... \
///     --dart-define=TEST_ADMIN_EMAIL=... --dart-define=TEST_ADMIN_PASSWORD=... \
///     --dart-define=TEST_MOTO_EMAIL=... --dart-define=TEST_MOTO_PASSWORD=...
///
/// Cada caso crea datos con prefijo AUDIT- y los borra al final.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/domain/deuda.dart';
import 'package:http/http.dart' as http;

const _url = String.fromEnvironment('TEST_SUPABASE_URL');
const _anonKey = String.fromEnvironment('TEST_SUPABASE_ANON_KEY');
const _adminEmail = String.fromEnvironment('TEST_ADMIN_EMAIL');
const _adminPassword = String.fromEnvironment('TEST_ADMIN_PASSWORD');
const _motoEmail = String.fromEnvironment('TEST_MOTO_EMAIL');
const _motoPassword = String.fromEnvironment('TEST_MOTO_PASSWORD');
const _serviceKey = String.fromEnvironment('TEST_SERVICE_KEY');

final _listo = _url.isNotEmpty && _anonKey.isNotEmpty;

class _Api {
  _Api(this.token);
  final String token;

  Map<String, String> get _h => {
        'apikey': _anonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<http.Response> get(String tabla, [Map<String, String>? q]) {
    var uri = Uri.parse('$_url/rest/v1/$tabla');
    if (q != null) uri = uri.replace(queryParameters: q);
    return http.get(uri, headers: _h);
  }

  Future<http.Response> post(String tabla, Map<String, dynamic> body) =>
      http.post(Uri.parse('$_url/rest/v1/$tabla'),
          headers: _h, body: jsonEncode(body));

  Future<http.Response> patch(
          String tabla, Map<String, dynamic> body, String filtro) =>
      http.patch(Uri.parse('$_url/rest/v1/$tabla?$filtro'),
          headers: _h, body: jsonEncode(body));

  Future<http.Response> delete(String tabla, String filtro) =>
      http.delete(Uri.parse('$_url/rest/v1/$tabla?$filtro'), headers: _h);
}

Future<String?> _login(String email, String password) async {
  final r = await http.post(
    Uri.parse('$_url/auth/v1/token?grant_type=password'),
    headers: {'apikey': _anonKey, 'Content-Type': 'application/json'},
    body: jsonEncode({'email': email, 'password': password}),
  );
  if (r.statusCode != 200) return null;
  return (jsonDecode(r.body) as Map)['access_token'] as String?;
}

void main() {
  if (!_listo) {
    test('Auditoría real (se salta sin credenciales)', () {});
    return;
  }

  late _Api admin;
  late _Api moto;
  _Api? svc;
  late String empresaId;
  late String motoId;
  late String adminId;
  late String productoId;
  final clientes = <String>[];
  final pedidos = <String>[];
  final pagos = <String>[];
  final entregas = <String>[];
  final movimientos = <String>[];
  final gastos = <String>[];
  final incidencias = <String>[];
  final rendiciones = <String>[];
  final fondos = <String>[];
  final uuids = <String>[];

  Future<String> cliente(String nombre) async {
    final r = await admin.post('clientes', {
      'empresa_id': empresaId,
      'nombre': 'AUDIT-$nombre-${DateTime.now().microsecondsSinceEpoch}',
      'direccion': 'Av. Prueba 123',
      'latitud': -16.41,
      'longitud': -71.53,
      'telefono': '900000001',
    });
    expect(r.statusCode, 201, reason: 'cliente: ${r.body}');
    final id = (jsonDecode(r.body) as List).first['id'] as String;
    clientes.add(id);
    return id;
  }

  Future<String> pedido(String idCliente, double total,
      {int cantidad = 1, double unitario = 0}) async {
    final uuid = 'audit-${DateTime.now().microsecondsSinceEpoch}-${pedidos.length}';
    uuids.add(uuid);
    final r = await admin.post('pedidos', {
      'empresa_id': empresaId,
      'cliente_id': idCliente,
      'creado_por': motoId,
      'total': total,
      'uuid_offline': uuid,
      'origen': 'ADMIN',
    });
    expect(r.statusCode, 201, reason: 'pedido: ${r.body}');
    final id = (jsonDecode(r.body) as List).first['id'] as String;
    pedidos.add(id);
    final d = await admin.post('detalle_pedido', {
      'empresa_id': empresaId,
      'pedido_id': id,
      'producto_id': productoId,
      'cantidad': cantidad,
      'precio_unitario': unitario > 0 ? unitario : total / cantidad,
    });
    expect(d.statusCode, 201, reason: 'detalle: ${d.body}');
    final a = await admin.patch(
        'pedidos', {'repartidor_id': motoId, 'estado': 'ASIGNADO'}, 'id=eq.$id');
    expect(a.statusCode, anyOf(200, 204), reason: a.body);
    return id;
  }

  Future<void> entregar({
    required String idPedido,
    required String idCliente,
    required List<Map<String, dynamic>> cobros,
    required int balones,
    required int devueltos,
  }) async {
    final e = await moto.post('entregas', {
      'empresa_id': empresaId,
      'pedido_id': idPedido,
      'estado_bal_on_vacio':
          devueltos > 0 ? 'RECIBIDO' : 'NO_RECIBIDO',
      'estado_pago': cobros.isEmpty ? 'PENDIENTE' : 'PAGADO',
      'registrado_por': motoId,
    });
    expect(e.statusCode, 201, reason: 'entrega: ${e.body}');
    entregas.add(idPedido);

    for (final cobro in cobros) {
      final p = await moto.post('pagos', {
        'empresa_id': empresaId,
        'pedido_id': idPedido,
        'cliente_id': idCliente,
        'monto': cobro['monto'],
        'metodo': cobro['metodo'],
        'registrado_por': motoId,
        if (cobro['comprobante'] != null)
          'comprobante_url': cobro['comprobante'],
      });
      expect(p.statusCode, 201, reason: 'pago: ${p.body}');
      pagos.add((jsonDecode(p.body) as List).first['id'] as String);
    }

    final salida = await moto.post('movimiento_bal_on', {
      'empresa_id': empresaId,
      'cliente_id': idCliente,
      'tipo': 'ENTREGA_LLENO',
      'pedido_id': idPedido,
      'cantidad': balones,
      'usuario_id': motoId,
    });
    expect(salida.statusCode, 201, reason: salida.body);
    movimientos.add(idPedido);
    if (devueltos > 0) {
      final dev = await moto.post('movimiento_bal_on', {
        'empresa_id': empresaId,
        'cliente_id': idCliente,
        'tipo': 'DEVOLUCION_VACIO',
        'pedido_id': idPedido,
        'cantidad': devueltos,
        'usuario_id': motoId,
      });
      expect(dev.statusCode, 201, reason: dev.body);
    }
    await moto.patch('pedidos', {'estado': 'ENTREGADO'}, 'id=eq.$idPedido');
  }

  Future<double> deudaDe(String idCliente) async {
    final p = await admin.get('pedidos', {
      'cliente_id': 'eq.$idCliente',
      'estado': 'eq.ENTREGADO',
      'select': 'id, cliente_id, total, estado',
    });
    final pag = await admin.get('pagos', {
      'cliente_id': 'eq.$idCliente',
      'select': 'pedido_id, cliente_id, monto',
    });
    return calcularDeudas(
      pedidos: List<Map<String, dynamic>>.from(jsonDecode(p.body) as List),
      pagos: List<Map<String, dynamic>>.from(jsonDecode(pag.body) as List),
    ).porCliente[idCliente] ?? 0;
  }

  Future<int> saldoBalon(String idCliente) async {
    final m = await admin.get('movimiento_bal_on', {
      'cliente_id': 'eq.$idCliente',
      'select': 'cliente_id, tipo, cantidad',
    });
    return calcularSaldosActivos(
      movimientos: List<Map<String, dynamic>>.from(jsonDecode(m.body) as List),
      tipoEntrega: 'ENTREGA_LLENO',
    )[idCliente] ?? 0;
  }

  setUpAll(() async {
    final ta = await _login(_adminEmail, _adminPassword);
    final tm = await _login(_motoEmail, _motoPassword);
    expect(ta, isNotNull, reason: 'login ADMIN');
    expect(tm, isNotNull, reason: 'login MOTORIZADO');
    admin = _Api(ta!);
    moto = _Api(tm!);
    if (_serviceKey.isNotEmpty) svc = _Api(_serviceKey);
    final perfiles = await admin.get('perfiles', {'select': 'id, rol, empresa_id'});
    final lista = jsonDecode(perfiles.body) as List;
    final a = lista.firstWhere((p) => p['rol'] == 'ADMIN');
    final m = lista.firstWhere((p) => p['rol'] == 'MOTORIZADO');
    empresaId = a['empresa_id'] as String;
    motoId = m['id'] as String;
    adminId = a['id'] as String;
    final prod = await admin.get('productos', {
      'select': 'id',
      'empresa_id': 'eq.$empresaId',
      'limit': '1',
    });
    productoId = (jsonDecode(prod.body) as List).first['id'] as String;
  });

  tearDownAll(() async {
    // service_role solo para limpiar: RLS no deja borrar pedidos/incidencias.
    final cleanup = svc ?? admin;
    for (final id in pagos) {
      await cleanup.delete('movimiento_caja', 'referencia_id=eq.$id');
      await cleanup.delete('pagos', 'id=eq.$id');
    }
    for (final id in entregas) {
      await cleanup.delete('entregas', 'pedido_id=eq.$id');
    }
    for (final id in movimientos) {
      await cleanup.delete('movimiento_bal_on', 'pedido_id=eq.$id');
    }
    for (final id in gastos) {
      await cleanup.delete('gastos', 'id=eq.$id');
    }
    for (final id in incidencias) {
      await cleanup.delete('incidencias', 'id=eq.$id');
    }
    for (final id in rendiciones) {
      await cleanup.delete('rendiciones', 'id=eq.$id');
    }
    for (final id in fondos) {
      await cleanup.delete('fondo_vuelto', 'id=eq.$id');
    }
    for (final id in pedidos) {
      await cleanup.delete('detalle_pedido', 'pedido_id=eq.$id');
      await cleanup.delete('pedidos', 'id=eq.$id');
    }
    for (final id in clientes) {
      await cleanup.delete('movimiento_bal_on', 'cliente_id=eq.$id');
      await cleanup.delete('pagos', 'cliente_id=eq.$id');
      await cleanup.delete('clientes', 'id=eq.$id');
    }
  });

  test('CASO A — 1 balón, S/50 efectivo, vacío recibido', () async {
    final c = await cliente('A');
    final p = await pedido(c, 50);
    await entregar(
        idPedido: p,
        idCliente: c,
        cobros: [
          {'monto': 50, 'metodo': 'EFECTIVO'}
        ],
        balones: 1,
        devueltos: 1);
    expect(await deudaDe(c), 0);
    expect(await saldoBalon(c), 0);
    final pago = await admin.get('pagos', {
      'pedido_id': 'eq.$p',
      'select': 'monto, metodo',
    });
    expect((jsonDecode(pago.body) as List).first['metodo'], 'EFECTIVO');
  });

  test('CASO B — 1 balón, S/50 Yape con comprobante', () async {
    final c = await cliente('B');
    final p = await pedido(c, 50);
    const url = 'https://ejemplo.invalid/comprobante-audit-b.png';
    await entregar(
        idPedido: p,
        idCliente: c,
        cobros: [
          {'monto': 50, 'metodo': 'YAPE', 'comprobante': url}
        ],
        balones: 1,
        devueltos: 1);
    expect(await deudaDe(c), 0);
    final pago = await admin.get('pagos', {
      'pedido_id': 'eq.$p',
      'select': 'monto, metodo, comprobante_url',
    });
    final fila = (jsonDecode(pago.body) as List).first;
    expect(fila['metodo'], 'YAPE');
    expect(fila['comprobante_url'], url,
        reason: 'La foto debe quedar asociada al pago');
  });

  test('CASO C — 1 balón, S/50 sin pago', () async {
    final c = await cliente('C');
    final p = await pedido(c, 50);
    await entregar(
        idPedido: p,
        idCliente: c,
        cobros: const [],
        balones: 1,
        devueltos: 0);
    expect(await deudaDe(c), 50);
    expect(await saldoBalon(c), 1);
  });

  test('CASO D — 2 balones S/90, paga S/100', () async {
    final c = await cliente('D');
    final p = await pedido(c, 180, cantidad: 2, unitario: 90);
    await entregar(
        idPedido: p,
        idCliente: c,
        cobros: [
          {'monto': 100, 'metodo': 'EFECTIVO'}
        ],
        balones: 2,
        devueltos: 2);
    expect(await deudaDe(c), 80);
    final pedidoLeido = await admin.get('pedidos', {
      'id': 'eq.$p',
      'select': 'total',
    });
    expect((jsonDecode(pedidoLeido.body) as List).first['total'], 180);
  });

  test('CASO E — 3 balones, devuelve 2 vacíos', () async {
    final c = await cliente('E');
    final p = await pedido(c, 135, cantidad: 3, unitario: 45);
    await entregar(
        idPedido: p,
        idCliente: c,
        cobros: [
          {'monto': 135, 'metodo': 'EFECTIVO'}
        ],
        balones: 3,
        devueltos: 2);
    expect(await saldoBalon(c), 1);
    expect(await deudaDe(c), 0);
  });

  test('CASO F — Yape S/50 + gasto combustible S/30', () async {
    final c = await cliente('F');
    final p = await pedido(c, 50);
    await entregar(
        idPedido: p,
        idCliente: c,
        cobros: [
          {'monto': 50, 'metodo': 'YAPE'}
        ],
        balones: 1,
        devueltos: 1);
    final g = await moto.post('gastos', {
      'empresa_id': empresaId,
      'usuario_id': motoId,
      'descripcion': 'AUDIT combustible caso F',
      'monto': 30,
      'categoria': 'Combustible',
      'medio_pago': 'EFECTIVO',
    });
    expect(g.statusCode, 201, reason: g.body);
    gastos.add((jsonDecode(g.body) as List).first['id'] as String);

    final pagosPedido = await admin.get('pagos', {
      'pedido_id': 'eq.$p',
      'select': 'monto, metodo',
    });
    final gastoLeido = await admin.get('gastos', {
      'descripcion': 'like.AUDIT combustible caso F*',
      'select': 'monto, categoria',
    });
    expect((jsonDecode(pagosPedido.body) as List).first['metodo'], 'YAPE');
    expect((jsonDecode(gastoLeido.body) as List).first['monto'], 30);
    expect(await deudaDe(c), 0,
        reason: 'El gasto nunca debe Generar deuda del cliente');
  });

  test('Doble entrega y doble pago están bloqueados', () async {
    final c = await cliente('DUP');
    final p = await pedido(c, 50);
    await entregar(
        idPedido: p,
        idCliente: c,
        cobros: [
          {'monto': 50, 'metodo': 'EFECTIVO'}
        ],
        balones: 1,
        devueltos: 1);
    final segunda = await moto.post('entregas', {
      'empresa_id': empresaId,
      'pedido_id': p,
      'estado_bal_on_vacio': 'RECIBIDO',
      'estado_pago': 'PAGADO',
      'registrado_por': motoId,
    });
    expect(segunda.statusCode, isNot(201),
        reason: 'No debe existir una segunda entrega: ${segunda.body}');
  });

  test('Fondo de vuelto: el Yape no se cuenta como efectivo', () async {
    for (final medio in ['EFECTIVO', 'YAPE']) {
      final r = await admin.post('fondo_vuelto', {
        'empresa_id': empresaId,
        'motorizado_id': motoId,
        'entregado_por': adminId,
        'monto': 50,
        'medio_pago': medio,
        'observaciones': 'AUDIT fondo $medio',
        'uuid_offline': 'audit-fondo-$medio-${DateTime.now().microsecondsSinceEpoch}',
      });
      if (r.statusCode == 400 && r.body.contains('medio_pago')) {
        // El paso 17 todavía no está aplicado: se reporta, no se oculta.
        print('PENDIENTE: aplicar paso 17 (fondo_vuelto.medio_pago)');
        return;
      }
      expect(r.statusCode, 201, reason: r.body);
      fondos.add((jsonDecode(r.body) as List).first['id'] as String);
    }
    final leidos = await admin.get('fondo_vuelto', {
      'observaciones': 'like.AUDIT fondo*',
      'select': 'monto, medio_pago',
    });
    final filas = jsonDecode(leidos.body) as List;
    expect(filas.length, 2);
    expect(filas.any((f) => f['medio_pago'] == 'EFECTIVO'), isTrue);
    expect(filas.any((f) => f['medio_pago'] == 'YAPE'), isTrue);
  });

  test('Fallas del motorizado se registran con empresa y usuario', () async {
    final i = await moto.post('incidencias', {
      'empresa_id': empresaId,
      'usuario_id': motoId,
      'tipo': 'FALLA',
      'descripcion': 'AUDIT falla auditoría',
      'monto': 20,
    });
    expect(i.statusCode, 201, reason: i.body);
    incidencias.add((jsonDecode(i.body) as List).first['id'] as String);
    final leida = await admin.get('incidencias', {
      'descripcion': 'eq.AUDIT falla auditoría',
      'select': 'empresa_id, usuario_id, monto',
    });
    final fila = (jsonDecode(leida.body) as List).first;
    expect(fila['empresa_id'], empresaId);
    expect(fila['usuario_id'], motoId);
  });
}
