/// Registro de pagos con evidencia (foto del comprobante).
///
/// Un pago por Yape SIN foto se permite solo con confirmación explícita en la
/// UI; aquí se conserva la ruta local y se sube a Storage. Si no hay red, la
/// operación entra al Outbox con la ruta local y se reintenta automáticamente.
library;

import 'package:uuid/uuid.dart';

import '../offline/outbox.dart';
import '../state/bus.dart';
import '../storage/comprobante_service.dart';
import 'pagos_repo.dart';
import 'sb.dart';

class PagoConComprobanteService {
  const PagoConComprobanteService();

  /// Devuelve true si se guardó online, false si quedó en la cola offline.
  Future<bool> registrar({
    required String empresaId,
    required String usuarioId,
    required String clienteId,
    required double monto,
    required String metodo,
    String? pedidoId,
    String? fotoPath,
  }) async {
    final uuid = Uuid().v4();
    String? comprobanteUrl;
    if (fotoPath != null) {
      comprobanteUrl = await ComprobanteService.subir(fotoPath);
    }

    final pago = <String, dynamic>{
      'empresa_id': empresaId,
      'pedido_id': pedidoId,
      'cliente_id': clienteId,
      'monto': monto,
      'metodo': metodo,
      'registrado_por': usuarioId,
      'uuid_offline': uuid,
      if (comprobanteUrl != null) 'comprobante_url': comprobanteUrl,
    };

    final fotoPendiente = fotoPath != null && comprobanteUrl == null;
    if (!fotoPendiente) {
      try {
        await pagosRepo.registrar(
          empresaId: empresaId,
          usuarioId: usuarioId,
          clienteId: clienteId,
          monto: monto,
          metodo: metodo,
          pedidoId: pedidoId,
          uuidOffline: uuid,
          comprobanteUrl: comprobanteUrl,
        );
        return true;
      } catch (e) {
        if (!esErrorDeRed(e)) rethrow;
      }
    }

    await Outbox.encolarPago(pago: pago, comprobanteLocalPath: fotoPath);
    SyncBus.dineroCambio();
    return false;
  }
}

const pagoConComprobante = PagoConComprobanteService();