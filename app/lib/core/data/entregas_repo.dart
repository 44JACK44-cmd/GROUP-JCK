/// Repositorio de entregas: cerrar un pedido con su resultado.
///
/// Reutiliza las tablas existentes: `entregas`, `pagos`, `movimiento_bal_on`,
/// `movimiento_fierro` y `auditoria`. No se crean tablas nuevas.
library;

import 'package:uuid/uuid.dart';

import '../domain/estado_pedido.dart';
import 'auditoria_repo.dart';
import 'sb.dart';

/// Estado del balón vacío en la entrega.
enum EstadoBalonVacio {
  recibido('RECIBIDO', 'Sí devolvió el vacío'),
  noRecibido('NO_RECIBIDO', 'No devolvió el vacío'),
  noAplica('NO_APLICA', 'No aplica');

  const EstadoBalonVacio(this.db, this.label);

  final String db;
  final String label;
}

/// Estado del fierro / soporte en la entrega.
enum EstadoFierro {
  devuelto('DEVUELTO', 'Devolvió el fierro'),
  pendiente('PENDIENTE', 'Fierro pendiente'),
  noAplica('NO_APLICA', 'No aplica');

  const EstadoFierro(this.db, this.label);

  final String db;
  final String label;
}

/// Datos que el motorizado (o el admin) registra al entregar.
class DatosEntrega {
  final double montoCobrado;
  final String metodo; // EFECTIVO | YAPE | PLIN | TRANSFERENCIA | OTRO
  final EstadoBalonVacio balonVacio;
  final EstadoFierro fierro;
  final int cantidadBalones;
  final int cantidadFierros;
  final String? observaciones;
  final bool sinConexion;

  const DatosEntrega({
    required this.montoCobrado,
    required this.metodo,
    required this.balonVacio,
    required this.fierro,
    this.cantidadBalones = 0,
    this.cantidadFierros = 0,
    this.observaciones,
    this.sinConexion = false,
  });

  bool quedanDeuda(double total) => montoCobrado + 0.009 < total;

  double deuda(double total) {
    final d = total - montoCobrado;
    return d > 0.009 ? d : 0;
  }
}

/// Resultado del cálculo del estado de pago.
enum EstadoPagoEntrega {
  pagado('PAGADO'),
  parcial('PARCIAL'),
  pendiente('PENDIENTE');

  const EstadoPagoEntrega(this.db);

  final String db;

  /// Calcula el estado de pago a partir del total y lo cobrado.
  static EstadoPagoEntrega calcular(double total, double cobrado) {
    if (cobrado + 0.009 >= total) return EstadoPagoEntrega.pagado;
    if (cobrado > 0.009) return EstadoPagoEntrega.parcial;
    return EstadoPagoEntrega.pendiente;
  }
}

class EntregasRepo {
  const EntregasRepo();

  /// Registra la entrega completa de un pedido.
  ///
  /// Hace, en orden:
  /// 1. `entregas` (una por pedido: la columna `pedido_id` es UNIQUE, así que
  ///    la base impide una doble entrega).
  /// 2. `pagos` (solo si se cobró algo) con método, monto, fecha y usuario.
  /// 3. `movimiento_bal_on` (ENTREGA_LLENO y, si devolvió el vacío, DEVOLUCION_VACIO).
  /// 4. `movimiento_fierro` si aplica.
  /// 5. `pedidos.estado = ENTREGADO`.
  /// 6. `auditoria`.
  ///
  /// Devuelve el id del pago generado (o null si quedó toda a deuda).
  Future<String?> registrarEntrega({
    required String empresaId,
    required String usuarioId,
    required String pedidoId,
    required String clienteId,
    required double total,
    required DatosEntrega datos,
  }) async {
    // 1. Entrega (protección contra doble entrega).
    final existente = await sb
        .from('entregas')
        .select('id')
        .eq('pedido_id', pedidoId)
        .maybeSingle();
    if (existente != null) {
      throw Exception('Este pedido ya fue entregado.');
    }

    final estadoPago = EstadoPagoEntrega.calcular(total, datos.montoCobrado);

    final entrega = {
      'empresa_id': empresaId,
      'pedido_id': pedidoId,
      'estado_bal_on_vacio': datos.balonVacio.db,
      'estado_pago': _estadoPagoDb(estadoPago),
      'registrado_por': usuarioId,
      'uuid_offline': const Uuid().v4(),
    };

    await sb.from('entregas').insert(entrega);

    // 2. Pago (solo si se cobró algo). Nunca se registra dos veces el mismo
    //    cobro: el pago nace con el id del pedido.
    String? pagoId;
    if (datos.montoCobrado > 0.009) {
      final pago = await sb
          .from('pagos')
          .insert({
            'empresa_id': empresaId,
            'pedido_id': pedidoId,
            'cliente_id': clienteId,
            'monto': datos.montoCobrado,
            'metodo': datos.metodo,
            'registrado_por': usuarioId,
            'uuid_offline': const Uuid().v4(),
          })
          .select('id')
          .single();
      pagoId = pago['id'] as String;
    }

    // 3. Balones: sale el lleno y, si el cliente devolvió el vacío, entra.
    if (datos.cantidadBalones > 0) {
      await sb.from('movimiento_bal_on').insert({
        'empresa_id': empresaId,
        'cliente_id': clienteId,
        'tipo': 'ENTREGA_LLENO',
        'pedido_id': pedidoId,
        'cantidad': datos.cantidadBalones,
        'usuario_id': usuarioId,
        'uuid_offline': const Uuid().v4(),
      });
      if (datos.balonVacio == EstadoBalonVacio.recibido) {
        await sb.from('movimiento_bal_on').insert({
          'empresa_id': empresaId,
          'cliente_id': clienteId,
          'tipo': 'DEVOLUCION_VACIO',
          'pedido_id': pedidoId,
          'cantidad': datos.cantidadBalones,
          'usuario_id': usuarioId,
          'uuid_offline': const Uuid().v4(),
        });
      }
    }

    // 4. Fierros: activo separado, nunca se mezcla con el balón.
    if (datos.cantidadFierros > 0) {
      await sb.from('movimiento_fierro').insert({
        'empresa_id': empresaId,
        'cliente_id': clienteId,
        'tipo': 'ENTREGA',
        'pedido_id': pedidoId,
        'cantidad': datos.cantidadFierros,
        'usuario_id': usuarioId,
        'uuid_offline': const Uuid().v4(),
      });
      if (datos.fierro == EstadoFierro.devuelto) {
        await sb.from('movimiento_fierro').insert({
          'empresa_id': empresaId,
          'cliente_id': clienteId,
          'tipo': 'DEVOLUCION',
          'pedido_id': pedidoId,
          'cantidad': datos.cantidadFierros,
          'usuario_id': usuarioId,
          'uuid_offline': const Uuid().v4(),
        });
      }
    }

    // 5. Cerrar el pedido.
    await sb.from('pedidos').update({'estado': 'ENTREGADO'}).eq('id', pedidoId);

    // 6. Auditoría.
    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'entrega',
      entidadId: pedidoId,
      accion: 'REGISTRAR_ENTREGA',
      usuarioId: usuarioId,
      detalle: {
        'total': total,
        'cobrado': datos.montoCobrado,
        'metodo': datos.metodo,
        'estado_pago': estadoPago.db,
        'deuda': datos.deuda(total),
        'balon_vacio': datos.balonVacio.db,
        'fierro': datos.fierro.db,
        if (datos.observaciones != null && datos.observaciones!.isNotEmpty)
          'observaciones': datos.observaciones,
      },
    );

    return pagoId;
  }

  /// El estado `PAGADO`/`PENDIENTE` que admite la tabla `entregas`.
  /// Un pago parcial se guarda como `PENDIENTE` (queda saldo por cobrar) y el
  /// detalle real vive en `pagos` + auditoría.
  static String _estadoPagoDb(EstadoPagoEntrega estado) =>
      estado == EstadoPagoEntrega.pagado ? 'PAGADO' : 'PENDIENTE';

  /// Registra el pedido como "no entregado" (el cliente no estaba, etc.).
  Future<void> registrarNoEntregado({
    required String empresaId,
    required String usuarioId,
    required String pedidoId,
    required String motivo,
  }) async {
    final existente = await sb
        .from('entregas')
        .select('id')
        .eq('pedido_id', pedidoId)
        .maybeSingle();
    if (existente != null) {
      throw Exception('Este pedido ya fue entregado.');
    }

    await sb.from('entregas').insert({
      'empresa_id': empresaId,
      'pedido_id': pedidoId,
      'estado_bal_on_vacio': 'NO_APLICA',
      'estado_pago': 'PENDIENTE',
      'registrado_por': usuarioId,
      'uuid_offline': const Uuid().v4(),
    });

    await sb.from('pedidos').update({'estado': 'NO_ENTREGADO'}).eq('id', pedidoId);

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'entrega',
      entidadId: pedidoId,
      accion: 'NO_ENTREGADO',
      usuarioId: usuarioId,
      detalle: {'motivo': motivo},
    );
  }

  /// Calcula cuánto se ha cobrado de un pedido y cuánto debe.
  Future<({double cobrado, double deuda, double total})> estadoCobro({
    required String pedidoId,
    required double total,
  }) async {
    final pagos = await sb
        .from('pagos')
        .select('monto')
        .eq('pedido_id', pedidoId);
    var cobrado = 0.0;
    for (final p in pagos) {
      cobrado += (p['monto'] as num? ?? 0).toDouble();
    }
    final deuda = (total - cobrado) > 0.009 ? total - cobrado : 0.0;
    return (cobrado: cobrado, deuda: deuda, total: total);
  }
}

const entregasRepo = EntregasRepo();

/// Etiquetas legibles de los estados de entrega.
String labelEstadoPago(String? db) => switch (db) {
      'PAGADO' => 'Pagado',
      'PARCIAL' => 'Pagó parcialmente',
      'PENDIENTE' => 'Pendiente',
      _ => 'Pendiente',
    };

String labelEstadoBalon(String? db) => switch (db) {
      'RECIBIDO' => 'Devolvió el vacío',
      'NO_RECIBIDO' => 'Vacío pendiente',
      'NO_APLICA' => 'No aplica',
      _ => 'No aplica',
    };

/// Transiciones válidas para la entrega (reutilizado por la UI).
EstadoPedido estadoPedidoDesde(String? db) => EstadoPedido.desdeDb(db);
