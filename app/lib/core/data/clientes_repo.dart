/// Repositorio de clientes: ficha, búsqueda, deuda y saldos de balones.
///
/// La deuda y el saldo de balones NUNCA se guardan: se calculan a partir de
/// `pedidos`, `pagos` y `movimiento_bal_on`, que son la fuente de verdad.
library;

import '../domain/deuda.dart';
import 'sb.dart';

/// Resumen económico de un cliente.
class ResumenCliente {
  final double deuda;
  final int balonesPendientes;
  final int fierrosPendientes;

  const ResumenCliente({
    this.deuda = 0,
    this.balonesPendientes = 0,
    this.fierrosPendientes = 0,
  });

  bool get tieneDeuda => deuda > 0.009;
  bool get tieneBalones => balonesPendientes > 0;
  bool get tieneFierros => fierrosPendientes > 0;
}

class ClientesRepo {
  const ClientesRepo();

  /// Lista clientes de la empresa.
  Future<List<Map<String, dynamic>>> listar({
    String? busqueda,
    bool soloActivos = true,
    int limite = 300,
  }) async {
    var q = sb.from('clientes').select(
      'id, nombre, telefono, tipo, direccion, referencia, latitud, longitud, observaciones, activo',
    );
    if (soloActivos) q = q.eq('activo', true);
    if (busqueda != null && busqueda.trim().isNotEmpty) {
      final t = busqueda.trim().replaceAll(',', ' ');
      q = q.or('nombre.ilike.%$t%,telefono.ilike.%$t%,direccion.ilike.%$t%');
    }
    final data = await q.order('nombre').limit(limite);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Búsqueda ligera para autocompletado (nombre o teléfono).
  Future<List<Map<String, dynamic>>> buscar(String texto, {int limite = 8}) async {
    final t = texto.trim();
    if (t.length < 2) return const [];
    final data = await sb
        .from('clientes')
        .select('id, nombre, telefono, direccion, referencia, latitud, longitud')
        .eq('activo', true)
        .or('nombre.ilike.%$t%,telefono.ilike.%$t%')
        .order('nombre')
        .limit(limite);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>?> obtener(String clienteId) async {
    final data = await sb
        .from('clientes')
        .select('id, nombre, telefono, tipo, direccion, referencia, latitud, longitud, observaciones, activo')
        .eq('id', clienteId)
        .maybeSingle();
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  /// Crea un cliente.
  Future<String> crear({
    required String empresaId,
    required String nombre,
    String? telefono,
    String tipo = 'PARTICULAR',
    String? direccion,
    String? referencia,
    String? zona,
    double? latitud,
    double? longitud,
    String? observaciones,
    String? uuidOffline,
  }) async {
    final data = await sb
        .from('clientes')
        .insert({
          'empresa_id': empresaId,
          'nombre': nombre,
          'telefono': telefono,
          'tipo': tipo,
          'direccion': direccion,
          'referencia': referencia,
          'zona': zona,
          'latitud': latitud,
          'longitud': longitud,
          'observaciones': observaciones,
          if (uuidOffline != null) 'uuid_offline': uuidOffline,
        })
        .select('id')
        .single();
    return data['id'] as String;
  }

  /// Actualiza la ficha del cliente (dirección, referencia, coordenadas…).
  Future<void> actualizar({
    required String clienteId,
    required String nombre,
    String? telefono,
    String? tipo,
    String? direccion,
    String? referencia,
    String? zona,
    double? latitud,
    double? longitud,
    String? observaciones,
    bool? activo,
  }) async {
    await sb.from('clientes').update({
      'nombre': nombre,
      'telefono': telefono,
      'tipo': tipo,
      'direccion': direccion,
      'referencia': referencia,
      'zona': zona,
      'latitud': latitud,
      'longitud': longitud,
      'observaciones': observaciones,
      if (activo != null) 'activo': activo,
      'actualizado_en': DateTime.now().toIso8601String(),
    }).eq('id', clienteId);
  }

  /// Precios especiales del cliente (si tiene) indexados por producto.
  Future<Map<String, double>> preciosDe(String clienteId) async {
    final data = await sb
        .from('precios_cliente')
        .select('producto_id, precio')
        .eq('cliente_id', clienteId);
    return {
      for (final p in data)
        p['producto_id'] as String: (p['precio'] as num? ?? 0).toDouble(),
    };
  }

  // ------------------------------------------------------------------
  // Deudas y saldos
  // ------------------------------------------------------------------

  /// Deuda total de un cliente.
  ///
  /// Deuda = Σ(total entregado − pagado de ese pedido) − abonos sueltos.
  /// Los abonos sin pedido se descuentan del total (el más antiguo primero).
  Future<double> deudaDe(String clienteId) async {
    final saldos = await _deudasPorCliente(clienteIds: [clienteId]);
    return saldos[clienteId] ?? 0;
  }

  /// Deuda de todos los clientes de la empresa (para la sección "Deudas").
  Future<Map<String, double>> _deudasPorCliente({
    List<String>? clienteIds,
    int limite = 2000,
  }) async {
    var qPedidos = sb.from('pedidos').select('id, cliente_id, total').eq('estado', 'ENTREGADO');
    if (clienteIds != null) qPedidos = qPedidos.inFilter('cliente_id', clienteIds);
    var qPagos = sb.from('pagos').select('monto, cliente_id, pedido_id');
    if (clienteIds != null) qPagos = qPagos.inFilter('cliente_id', clienteIds);

    final res = await Future.wait([
      qPedidos.limit(limite),
      qPagos.limit(limite * 2),
    ]);

    return calcularDeudas(
      pedidos: List<Map<String, dynamic>>.from(res[0] as List),
      pagos: List<Map<String, dynamic>>.from(res[1] as List),
    ).porCliente;
  }

  /// Deuda de todos los clientes (mapa clienteId → monto).
  Future<Map<String, double>> deudasGlobales() => _deudasPorCliente();

  /// Saldo de balones y fierros por cliente (entregados − devueltos).
  Future<Map<String, int>> saldosBalones() async {
    final data = await sb
        .from('movimiento_bal_on')
        .select('cliente_id, tipo, cantidad')
        .limit(5000);
    return calcularSaldosActivos(
      movimientos: List<Map<String, dynamic>>.from(data),
      tipoEntrega: 'ENTREGA_LLENO',
    );
  }

  Future<Map<String, int>> saldosFierros() async {
    final data = await sb
        .from('movimiento_fierro')
        .select('cliente_id, tipo, cantidad')
        .limit(5000);
    return calcularSaldosActivos(
      movimientos: List<Map<String, dynamic>>.from(data),
      tipoEntrega: 'ENTREGA',
    );
  }

  /// Resumen completo de un cliente (deuda + balones + fierros).
  Future<ResumenCliente> resumenDe(String clienteId) async {
    final res = await Future.wait([
      deudaDe(clienteId),
      saldosBalones(),
      saldosFierros(),
    ]);
    return ResumenCliente(
      deuda: res[0] as double,
      balonesPendientes: (res[1] as Map<String, int>)[clienteId] ?? 0,
      fierrosPendientes: (res[2] as Map<String, int>)[clienteId] ?? 0,
    );
  }

  /// Últimos pedidos del cliente.
  Future<List<Map<String, dynamic>>> ultimosPedidos(String clienteId, {int limite = 10}) async {
    final data = await sb
        .from('pedidos')
        .select('id, numero, fecha, total, estado, forma_pago, entregas(estado_pago)')
        .eq('cliente_id', clienteId)
        .order('fecha', ascending: false)
        .limit(limite);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Total de pedidos del cliente.
  Future<int> totalPedidos(String clienteId) async {
    final res = await sb.from('pedidos').select('id').eq('cliente_id', clienteId).count();
    return res.count;
  }
}

const clientesRepo = ClientesRepo();
