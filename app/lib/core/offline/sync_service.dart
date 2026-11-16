/// Sincronización automática de la cola offline.
///
/// El `Outbox` guarda los pedidos, entregas y cobros hechos sin internet.
/// Este servicio los reintenta cuando vuelve la conexión, al volver a la app
/// y cada minuto mientras esté abierta. Nunca borra nada si el envío falla.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../realtime/realtime_service.dart';
import '../state/bus.dart';
import 'outbox.dart';

class SyncService with WidgetsBindingObserver {
  SyncService._();

  static final SyncService instance = SyncService._();

  StreamSubscription<List<ConnectivityResult>>? _conexion;
  Timer? _reloj;
  bool _corriendo = false;
  DateTime? ultimaSincronizacion;

  bool get activo => _conexion != null;

  /// Empieza a escuchar la conexión. Se puede llamar varias veces sin efecto.
  void start() {
    if (activo) return;
    WidgetsBinding.instance.addObserver(this);
    _conexion = Connectivity().onConnectivityChanged.listen((resultados) {
      final hayRed = resultados.any((r) => r != ConnectivityResult.none);
      SyncBus.conexionCambio(hayRed);
      if (hayRed) {
        RealtimeService.instance.reconectar();
        sincronizar();
      }
    });
    _reloj = Timer.periodic(const Duration(seconds: 60), (_) => sincronizar());
    sincronizar();
  }

  void stop() {
    _conexion?.cancel();
    _conexion = null;
    _reloj?.cancel();
    _reloj = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sincronizar();
  }

  /// Reintenta la cola. Devuelve cuántas operaciones se sincronizaron.
  Future<int> sincronizar() async {
    if (_corriendo) return 0;
    if (Supabase.instance.client.auth.currentUser == null) return 0;
    _corriendo = true;
    SyncBus.sincronizandoCambio(true);
    try {
      final enviadas = await Outbox.procesar();
      if (enviadas > 0) ultimaSincronizacion = DateTime.now();
      return enviadas;
    } catch (_) {
      return 0;
    } finally {
      _corriendo = false;
      SyncBus.sincronizandoCambio(false);
    }
  }

  /// Operaciones guardadas esperando conexión.
  Future<int> pendientes() => Outbox.pendientes();
}
