/// Suscripción Realtime ÚNICA para toda la aplicación.
///
/// Antes cada pantalla abría su propio canal: eso multiplicaba conexiones,
/// firing de consultas y fugas de memoria al rotar pantallas. Ahora hay un solo
/// canal global que traduce cada cambio de tabla en un aviso de [SyncBus].
///
/// Las pantallas solo escuchan `SyncBus` (en `initState` y se desuscriben en
/// `dispose`). Así un cambio hecho en otro teléfono llega sin recargar, y un
/// cambio hecho en este teléfono llega por el bus aunque Realtime no esté activo.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sb.dart';
import '../state/bus.dart';

class RealtimeService {
  RealtimeService._();

  static final RealtimeService instance = RealtimeService._();

  static const _canalId = 'gasapp-global';

  RealtimeChannel? _canal;
  bool _activo = false;

  bool get activo => _activo;

  /// Tablas que mueven la interfaz. Todas publicadas en el paso 15.
  static const _tablas = <String>{
    'pedidos',
    'detalle_pedido',
    'entregas',
    'pagos',
    'gastos',
    'incidencias',
    'clientes',
    'movimiento_bal_on',
    'movimiento_fierro',
    'rendiciones',
    'fondo_vuelto',
    'cajas',
    'movimiento_caja',
    'ubicaciones_motorizado',
  };

  void start() {
    if (_activo) return;
    _activo = true;

    var canal = sb.channel(_canalId);
    for (final tabla in _tablas) {
      canal = canal.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: tabla,
        callback: (_) => _avisar(tabla),
      );
    }
    _canal = canal.subscribe();
  }

  void stop() {
    if (!_activo) return;
    _activo = false;
    final canal = _canal;
    _canal = null;
    if (canal != null) {
      try {
        sb.removeChannel(canal);
      } catch (_) {
        // El canal ya se cerró (p. ej. al cerrar la app).
      }
    }
  }

  /// Se llama al volver Internet para re-suscribir si Supabase cerró el canal.
  void reconectar() {
    if (!_activo) return;
    stop();
    start();
  }

  static void _avisar(String tabla) {
    switch (tabla) {
      case 'pedidos':
      case 'detalle_pedido':
        SyncBus.pedidoYdinero();
        break;
      case 'entregas':
      case 'pagos':
        SyncBus.dineroCambio();
        SyncBus.pedidosCambiaron();
        break;
      case 'gastos':
      case 'incidencias':
      case 'movimiento_bal_on':
      case 'movimiento_fierro':
      case 'cajas':
      case 'movimiento_caja':
        SyncBus.dineroCambio();
        break;
      case 'rendiciones':
      case 'fondo_vuelto':
        SyncBus.rendicionCambio();
        break;
      case 'clientes':
        SyncBus.movimientosCambiaron();
        break;
      case 'ubicaciones_motorizado':
        SyncBus.ubicacionCambio();
        break;
    }
  }
}
