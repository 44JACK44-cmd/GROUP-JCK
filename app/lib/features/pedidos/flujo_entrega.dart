/// Acción de entrega reutilizable.
///
/// Se usa tanto en el detalle del pedido como en la tarjeta del motorizado:
/// el mismo flujo, sin duplicar lógica. Devuelve `true` si la entrega se
/// registró (o se encoló sin conexión) correctamente.
///
/// La foto de Yape se sube a Supabase Storage y su URL se guarda en `pagos`.
/// Si no se pudo subir, la operación entra a la cola offline con la ruta local
/// para reintentarla después: nunca se pierde el comprobante.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/entregas_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/domain/resumen_pedido.dart';
import '../../core/offline/outbox.dart';
import '../../core/storage/comprobante_service.dart';
import '../auth/auth_controller.dart';
import 'entrega_sheet.dart';

Future<bool> ejecutarEntrega(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> pedido, {
  double? total,
  int? cantidadBalones,
  int? cantidadFierros,
}) async {
  final auth = ref.read(authProvider);
  final t = total ?? (pedido['total'] as num? ?? 0).toDouble();
  final balones = cantidadBalones ?? balonesDe(pedido);
  final fierros = cantidadFierros ?? fierrosDe(pedido);

  final datos = await mostrarFormularioEntrega(
    context,
    total: t,
    cantidadBalones: balones,
    cantidadFierros: fierros,
  );
  if (datos == null) return false;

  final pedidoId = pedido['id'] as String;
  final clienteId = pedido['cliente_id'] as String;
  final empresaId = auth.empresaId!;

  // Subir el comprobante ANTES de cerrar el pedido. Si falla la subida, la
  // entrega se encola para que el reintento vuelva a intentar la foto.
  String? comprobanteUrl;
  final fotoLocal = datos.comprobanteLocalPath;
  if (datos.metodo == 'YAPE' && datos.montoCobrado > 0 && fotoLocal != null) {
    comprobanteUrl = await ComprobanteService.subir(fotoLocal);
  }
  final fotoPendiente = fotoLocal != null && comprobanteUrl == null;

  if (!fotoPendiente) {
    try {
      await entregasRepo.registrarEntrega(
        empresaId: empresaId,
        usuarioId: auth.usuarioId!,
        pedidoId: pedidoId,
        clienteId: clienteId,
        total: t,
        datos: datos,
        comprobanteUrl: comprobanteUrl,
      );
      pedido['estado'] = 'ENTREGADO';
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeEntrega(datos, t))),
        );
      }
      return true;
    } catch (e) {
      if (!esErrorDeRed(e)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e is Exception
                  ? e.toString().replaceFirst('Exception: ', '')
                  : 'No se pudo entregar el pedido.'),
            ),
          );
        }
        return false;
      }
      // Sin conexión: se encola abajo.
    }
  }

  await Outbox.encolarEntrega(
    entrega: {
      'empresa_id': empresaId,
      'pedido_id': pedidoId,
      'estado_bal_on_vacio': datos.balonVacio.db,
      'estado_pago': datos.montoCobrado + 0.009 >= t ? 'PAGADO' : 'PENDIENTE',
      'registrado_por': auth.usuarioId,
    },
    pago: datos.montoCobrado > 0
        ? {
            'empresa_id': empresaId,
            'pedido_id': pedidoId,
            'cliente_id': clienteId,
            'monto': datos.montoCobrado,
            'metodo': datos.metodo,
            'registrado_por': auth.usuarioId,
          }
        : null,
    movimientoBalon: balones > 0
        ? {
            'empresa_id': empresaId,
            'cliente_id': clienteId,
            'tipo': 'ENTREGA_LLENO',
            'pedido_id': pedidoId,
            'cantidad': balones,
            'usuario_id': auth.usuarioId,
          }
        : null,
    movimientoFierro: fierros > 0
        ? {
            'empresa_id': empresaId,
            'cliente_id': clienteId,
            'tipo': 'ENTREGA',
            'pedido_id': pedidoId,
            'cantidad': fierros,
            'usuario_id': auth.usuarioId,
          }
        : null,
    comprobanteLocalPath: fotoLocal,
    balonDevuelto: datos.balonVacio == EstadoBalonVacio.recibido,
    fierroDevuelto: datos.fierro == EstadoFierro.devuelto,
  );
  pedido['estado'] = 'ENTREGADO';
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          fotoPendiente
              ? 'Entrega guardada. El comprobante quedó pendiente de subida '
                  'y se reintentará automáticamente.'
              : 'Sin conexión: la entrega quedó guardada y se enviará sola.',
        ),
      ),
    );
  }
  return true;
}

String _mensajeEntrega(DatosEntrega datos, double total) {
  if (datos.montoCobrado <= 0.009) return 'Entregado. Quedó una deuda de ${dinero(total)}.';
  if (datos.montoCobrado + 0.009 >= total) return 'Entregado. Cobrado ${dinero(datos.montoCobrado)}.';
  return 'Entregado. Pagó ${dinero(datos.montoCobrado)}, debe ${dinero(total - datos.montoCobrado)}.';
}
