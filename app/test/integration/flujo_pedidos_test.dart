/// PRUEBA DE INTEGRACIÓN: el flujo completo de pedidos contra Supabase real.
///
/// Verifica, de punta a punta:
///   BASE DE DATOS → SUPABASE → SERVICIO → ESTADO → PERSISTENCIA
///
/// Se ejecuta solo si se pasan las credenciales por --dart-define:
///   flutter test test/integration \
///     --dart-define=TEST_SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=TEST_SUPABASE_ANON_KEY=eyJ... \
///     --dart-define=TEST_ADMIN_EMAIL=admin@grupojck.app \
///     --dart-define=TEST_ADMIN_PASSWORD=admin123 \
///     --dart-define=TEST_MOTO_EMAIL=999888777@grupojck.app \
///     --dart-define=TEST_MOTO_PASSWORD=demo123
///
/// Sin esas variables la prueba se salta (no falla) para no romper el
/// `flutter test` normal del proyecto.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _url = String.fromEnvironment('TEST_SUPABASE_URL');
const _anonKey = String.fromEnvironment('TEST_SUPABASE_ANON_KEY');
const _adminEmail = String.fromEnvironment('TEST_ADMIN_EMAIL');
const _adminPassword = String.fromEnvironment('TEST_ADMIN_PASSWORD');
const _motoEmail = String.fromEnvironment('TEST_MOTO_EMAIL');
const _motoPassword = String.fromEnvironment('TEST_MOTO_PASSWORD');

final _configurado = _url.isNotEmpty &&
    _anonKey.isNotEmpty &&
    _adminEmail.isNotEmpty &&
    _adminPassword.isNotEmpty;

/// Cliente mínimo de la API REST de PostgREST con el token del usuario.
class Api {
  Api(this.token);

  final String token;

  Map<String, String> get _headers => {
        'apikey': _anonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<http.Response> get(String path, {Map<String, String>? query}) {
    var uri = Uri.parse('$_url/rest/v1/$path');
    if (query != null) uri = uri.replace(queryParameters: query);
    return http.get(uri, headers: _headers);
  }

  Future<http.Response> post(String path, Map<String, dynamic> body) => http.post(
        Uri.parse('$_url/rest/v1/$path'),
        headers: _headers,
        body: jsonEncode(body),
      );

  Future<http.Response> patch(String path, Map<String, dynamic> body, String query) =>
      http.patch(
        Uri.parse('$_url/rest/v1/$path?$query'),
        headers: _headers,
        body: jsonEncode(body),
      );

  Future<http.Response> delete(String path, String query) => http.delete(
        Uri.parse('$_url/rest/v1/$path?$query'),
        headers: _headers,
      );
}

Future<String?> _login(String email, String password) async {
  final r = await http.post(
    Uri.parse('$_url/auth/v1/token?grant_type=password'),
    headers: {'apikey': _anonKey, 'Content-Type': 'application/json'},
    body: jsonEncode({'email': email, 'password': password}),
  );
  if (r.statusCode != 200) return null;
  final j = jsonDecode(r.body);
  return j['access_token'] as String?;
}

void main() {
  if (!_configurado) {
    test('Prueba de integración (flujo de pedidos)', () {
      print(
        '⏭  Saltada: faltan las variables TEST_SUPABASE_URL / TEST_SUPABASE_ANON_KEY / '
        'TEST_ADMIN_EMAIL / TEST_ADMIN_PASSWORD. '
        'Ver la cabecera del archivo para ejecutarla.',
      );
    });
    return;
  }

  late Api admin;
  late Api moto;
  late String adminId;
  late String motoId;
  late String empresaId;
  late String productoId;

  // Datos de la prueba (se limpian al final).
  String? clienteId;
  String? pedidoId;

  setUpAll(() async {
    final tokenAdmin = await _login(_adminEmail, _adminPassword);
    final tokenMoto = await _login(_motoEmail, _motoPassword);
    expect(tokenAdmin, isNotNull, reason: 'El ADMIN debe poder iniciar sesión');
    expect(tokenMoto, isNotNull, reason: 'El MOTORIZADO debe poder iniciar sesión');
    admin = Api(tokenAdmin!);
    moto = Api(tokenMoto!);

    final perfil = await admin.get('perfiles', query: {'id': 'eq.${_perfilIdDe(tokenAdmin)}'});
    expect(perfil.statusCode, 200);

    // Identidad del admin y del motorizado desde sus perfiles.
    final perfiles = await admin.get('perfiles', query: {'select': 'id, nombre, rol, empresa_id'});
    final lista = jsonDecode(perfiles.body) as List;
    final adminPerfil = lista.firstWhere((p) => p['rol'] == 'ADMIN');
    final motoPerfil = lista.firstWhere((p) => p['rol'] == 'MOTORIZADO');
    adminId = adminPerfil['id'] as String;
    motoId = motoPerfil['id'] as String;
    empresaId = adminPerfil['empresa_id'] as String;

    final productos = await admin.get('productos',
        query: {'select': 'id, nombre, precio_base', 'empresa_id': 'eq.$empresaId', 'limit': '1'});
    final listaProductos = jsonDecode(productos.body) as List;
    expect(listaProductos, isNotEmpty, reason: 'La empresa debe tener al menos un producto');
    productoId = listaProductos.first['id'] as String;
  });

  tearDownAll(() async {
    if (pedidoId != null) {
      await admin.delete('detalle_pedido', 'pedido_id=eq.$pedidoId');
      await admin.delete('entregas', 'pedido_id=eq.$pedidoId');
      await admin.delete('pagos', 'pedido_id=eq.$pedidoId');
      await admin.delete('movimiento_bal_on', 'pedido_id=eq.$pedidoId');
      await admin.delete('pedidos', 'id=eq.$pedidoId');
    }
    if (clienteId != null) {
      await admin.delete('movimiento_bal_on', 'cliente_id=eq.$clienteId');
      await admin.delete('pagos', 'cliente_id=eq.$clienteId');
      await admin.delete('clientes', 'id=eq.$clienteId');
    }
  });

  test('1. ADMIN registra un cliente con dirección y coordenadas', () async {
    final r = await admin.post('clientes', {
      'empresa_id': empresaId,
      'nombre': 'Cliente Prueba Flujo',
      'telefono': '900111000',
      'direccion': 'Av. Ejército 123',
      'referencia': 'A dos cuadras del parque',
      'latitud': -16.4090,
      'longitud': -71.5375,
    });
    expect(r.statusCode, 201, reason: 'No se pudo crear el cliente: ${r.body}');
    clienteId = (jsonDecode(r.body) as List).first['id'] as String;

    final leido = await admin.get('clientes', query: {'id': 'eq.$clienteId', 'select': '*'});
    final datos = (jsonDecode(leido.body) as List).first;
    expect(datos['direccion'], 'Av. Ejército 123');
    expect(datos['referencia'], 'A dos cuadras del parque');
    expect(datos['latitud'], isNotNull);
    expect((datos['latitud'] as num).toDouble(), closeTo(-16.4090, 0.0001));
  });

  test('2. ADMIN crea el pedido y sus productos (con empresa_id)', () async {
    // Cabecera
    final rPedido = await admin.post('pedidos', {
      'empresa_id': empresaId,
      'cliente_id': clienteId,
      'creado_por': adminId,
      'total': 45,
      'uuid_offline': 'test-flujo-${DateTime.now().millisecondsSinceEpoch}',
    });
    expect(rPedido.statusCode, 201, reason: 'No se pudo crear el pedido: ${rPedido.body}');
    pedidoId = (jsonDecode(rPedido.body) as List).first['id'] as String;

    // Detalle: CON empresa_id (esto es lo que fallaba antes con 42501).
    final rDetalle = await admin.post('detalle_pedido', {
      'empresa_id': empresaId,
      'pedido_id': pedidoId,
      'producto_id': productoId,
      'cantidad': 1,
      'precio_unitario': 45,
    });
    expect(rDetalle.statusCode, 201,
        reason: 'El detalle del pedido debe crearse con empresa_id: ${rDetalle.body}');
  });

  test('3. El detalle SIN empresa_id es rechazado por RLS (regresión del bug)', () async {
    final r = await admin.post('detalle_pedido', {
      'pedido_id': pedidoId,
      'producto_id': productoId,
      'cantidad': 1,
      'precio_unitario': 45,
    });
    expect(_esRechazoPorRls(r), isTrue,
        reason: 'Sin empresa_id la política RLS debe rechazar el detalle');
  });

  test('4. El pedido aparece en la lista del ADMIN', () async {
    final r = await admin.get('pedidos', query: {'id': 'eq.$pedidoId', 'select': '*'});
    final lista = jsonDecode(r.body) as List;
    expect(lista, hasLength(1));
    expect(lista.first['estado'], 'NUEVO');
    expect(lista.first['total'], 45);
  });

  test('5. El ADMIN asigna el pedido al motorizado', () async {
    final r = await admin.patch(
      'pedidos',
      {'repartidor_id': motoId, 'estado': 'ASIGNADO'},
      'id=eq.$pedidoId',
    );
    expect(r.statusCode, anyOf(200, 204), reason: r.body);

    final leido = await admin.get('pedidos', query: {'id': 'eq.$pedidoId', 'select': '*'});
    expect((jsonDecode(leido.body) as List).first['estado'], 'ASIGNADO');
  });

  test('6. El MOTORIZADO ve el pedido en "Mis pedidos"', () async {
    final r = await moto.get('pedidos', query: {
      'repartidor_id': 'eq.$motoId',
      'estado': 'in.(ASIGNADO,EN_CAMINO)',
      'select': 'id, numero, estado, total, clientes(nombre, direccion, latitud, longitud)',
    });
    expect(r.statusCode, 200, reason: r.body);
    final lista = jsonDecode(r.body) as List;
    final pedido = lista.firstWhere((p) => p['id'] == pedidoId);
    // El motorizado ve la dirección y las coordenadas DEL CLIENTE.
    expect(pedido['clientes']['direccion'], 'Av. Ejército 123');
    expect(pedido['clientes']['latitud'], isNotNull);
  });

  test('7. El MOTORIZADO NO puede crear pedidos ni clientes', () async {
    final pedido = await moto.post('pedidos', {
      'empresa_id': empresaId,
      'cliente_id': clienteId,
      'total': 45,
    });
    expect(_esRechazoPorRls(pedido), isTrue,
        reason: 'El motorizado no tiene permiso para crear pedidos');

    final cliente = await moto.post('clientes', {
      'empresa_id': empresaId,
      'nombre': 'Intruso',
    });
    expect(_esRechazoPorRls(cliente), isTrue,
        reason: 'El motorizado no tiene permiso para crear clientes');
  });

  test('8. El MOTORIZADO entrega: registra entrega, pago Yape y balón', () async {
    // El pedido pasa a EN_CAMINO.
    final rCamino = await moto.patch('pedidos', {'estado': 'EN_CAMINO'}, 'id=eq.$pedidoId');
    expect(rCamino.statusCode, anyOf(200, 204));

    // Entrega (pedido_id es UNIQUE: impide la doble entrega).
    final rEntrega = await moto.post('entregas', {
      'empresa_id': empresaId,
      'pedido_id': pedidoId,
      'estado_bal_on_vacio': 'NO_RECIBIDO',
      'estado_pago': 'PAGADO',
      'registrado_por': motoId,
    });
    expect(rEntrega.statusCode, 201, reason: rEntrega.body);

    // Pago con Yape.
    final rPago = await moto.post('pagos', {
      'empresa_id': empresaId,
      'pedido_id': pedidoId,
      'cliente_id': clienteId,
      'monto': 45,
      'metodo': 'YAPE',
      'registrado_por': motoId,
    });
    expect(rPago.statusCode, 201, reason: rPago.body);

    // Salida del balón lleno.
    final rBalon = await moto.post('movimiento_bal_on', {
      'empresa_id': empresaId,
      'cliente_id': clienteId,
      'tipo': 'ENTREGA_LLENO',
      'pedido_id': pedidoId,
      'cantidad': 1,
      'usuario_id': motoId,
    });
    expect(rBalon.statusCode, 201, reason: rBalon.body);

    // Cierre del pedido.
    final rCierre = await moto.patch('pedidos', {'estado': 'ENTREGADO'}, 'id=eq.$pedidoId');
    expect(rCierre.statusCode, anyOf(200, 204));
  });

  test('9. Una segunda entrega del mismo pedido es rechazada', () async {
    final r = await moto.post('entregas', {
      'empresa_id': empresaId,
      'pedido_id': pedidoId,
      'estado_bal_on_vacio': 'NO_RECIBIDO',
      'estado_pago': 'PAGADO',
      'registrado_por': motoId,
    });
    expect(_esDuplicado(r), isTrue,
        reason: 'No se puede entregar dos veces el mismo pedido');
  });

  test('10. El ADMIN ve la entrega, el pago y el método', () async {
    final pedido = await admin.get('pedidos',
        query: {'id': 'eq.$pedidoId', 'select': 'id, estado, total, entregas(estado_pago)'});
    final datos = (jsonDecode(pedido.body) as List).first;
    expect(datos['estado'], 'ENTREGADO');

    final pagos = await admin.get('pagos',
        query: {'pedido_id': 'eq.$pedidoId', 'select': 'monto, metodo, registrado_por, fecha'});
    final listaPagos = jsonDecode(pagos.body) as List;
    expect(listaPagos, hasLength(1));
    expect(listaPagos.first['monto'], 45);
    expect(listaPagos.first['metodo'], 'YAPE');
    expect(listaPagos.first['registrado_por'], motoId);
    expect(listaPagos.first['fecha'], isNotNull);
  });

  test('11. Con pago completo el cliente NO tiene deuda', () async {
    final pagos = await admin.get('pagos',
        query: {'cliente_id': 'eq.$clienteId', 'select': 'monto, pedido_id'});
    final lista = jsonDecode(pagos.body) as List;
    final cobrado = lista.fold<double>(0, (s, p) => s + (p['monto'] as num));
    expect(cobrado, 45);
    expect(45 - cobrado, 0);
  });

  test('12. El balón queda pendiente de devolución', () async {
    final movs = await admin.get('movimiento_bal_on',
        query: {'cliente_id': 'eq.$clienteId', 'select': 'tipo, cantidad'});
    final lista = jsonDecode(movs.body) as List;
    final saldo = lista.fold<int>(
      0,
      (s, m) => s + (m['tipo'] == 'ENTREGA_LLENO' ? m['cantidad'] as int : -(m['cantidad'] as int)),
    );
    expect(saldo, 1, reason: 'El cliente debe 1 balón vacío');

    // Devolución posterior: el saldo baja a 0 y queda la trazabilidad.
    final r = await admin.post('movimiento_bal_on', {
      'empresa_id': empresaId,
      'cliente_id': clienteId,
      'tipo': 'DEVOLUCION_VACIO',
      'pedido_id': pedidoId,
      'cantidad': 1,
      'usuario_id': adminId,
    });
    expect(r.statusCode, 201, reason: r.body);

    final movs2 = await admin.get('movimiento_bal_on',
        query: {'cliente_id': 'eq.$clienteId', 'select': 'tipo, cantidad'});
    final lista2 = jsonDecode(movs2.body) as List;
    expect(lista2, hasLength(2), reason: 'Nada se borra: quedan los dos movimientos');
    final saldo2 = lista2.fold<int>(
      0,
      (s, m) => s + (m['tipo'] == 'ENTREGA_LLENO' ? m['cantidad'] as int : -(m['cantidad'] as int)),
    );
    expect(saldo2, 0);
  });

  test('13. AISLAMIENTO MULTIEMPRESA: el admin no ve datos de otra empresa', () async {
    final r = await admin.get('pedidos', query: {'select': 'empresa_id'});
    expect(r.statusCode, 200);
    final lista = jsonDecode(r.body) as List;
    for (final p in lista) {
      expect(p['empresa_id'], empresaId,
          reason: 'RLS debe devolver solo pedidos de la empresa del usuario');
    }

    // Forzar el filtro hacia otra empresa no devuelve nada.
    final rForzado = await admin.get('pedidos', query: {
      'empresa_id': 'neq.$empresaId',
      'select': 'id',
    });
    expect(jsonDecode(rForzado.body), isEmpty);
  });

  test('14. No se puede escribir en otra empresa (RLS)', () async {
    final r = await admin.post('clientes', {
      'empresa_id': '00000000-0000-0000-0000-000000000000',
      'nombre': 'Intruso',
    });
    expect(_esRechazoPorRls(r), isTrue,
        reason: 'No se puede crear un cliente en otra empresa');
  });
}

/// El id del perfil es el mismo que el del usuario autenticado.
/// Se obtiene del propio token para no depender de la lista.
String _perfilIdDe(String token) {
  // El JWT lleva el "sub" (id del usuario).
  final partes = token.split('.');
  final payload = jsonDecode(utf8.decode(base64Url.decode(partes[1])));
  return payload['sub'] as String;
}

/// PostgREST responde 403 (o 42501 según la versión) cuando RLS rechaza la
/// escritura. Aceptamos ambos.
bool _esRechazoPorRls(http.Response r) =>
    r.statusCode == 403 ||
    r.statusCode == 42501 ||
    (r.body.contains('row-level security') || r.body.contains('42501'));

/// Un pedido ya entregado no se puede volver a entregar: la columna
/// `entregas.pedido_id` es UNIQUE (PostgREST devuelve 400 con 23505).
bool _esDuplicado(http.Response r) =>
    r.statusCode == 409 ||
    (r.body.contains('23505') || r.body.contains('duplicate key'));
