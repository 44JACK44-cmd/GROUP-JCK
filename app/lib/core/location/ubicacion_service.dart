/// Seguimiento GPS del motorizado.
///
/// Reglas de la fase:
///  * Solo comparte ubicación cuando el motorizado lo activa.
///  * Nunca cada segundo: como mínimo 30 s y solo si se movió unos metros.
///  * Se detiene al cerrar sesión.
///  * Si el permiso está negado, se dice claramente: "Sin permiso".
///
/// No es rastreo permanente: la app no pide ubicación en segundo plano.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/sb.dart';
import '../data/ubicaciones_repo.dart';
import '../state/bus.dart';

enum EstadoGps {
  apagado('Ubicación pausada'),
  activo('Ubicación activa'),
  sinPermiso('Sin permiso de ubicación'),
  sinSesion('Sin sesión');

  const EstadoGps(this.label);

  final String label;
}

class UbicacionService {
  UbicacionService._();

  static final UbicacionService instance = UbicacionService._();

  static const _prefActivo = 'gasapp_gps_activo';

  final ValueNotifier<EstadoGps> estado = ValueNotifier(EstadoGps.apagado);
  final ValueNotifier<DateTime?> ultimoEnvio = ValueNotifier<DateTime?>(null);

  Timer? _reloj;
  String? _usuarioId;
  String? _empresaId;
  Position? _ultima;
  bool _enviando = false;

  bool get activo => _reloj != null;

  /// Llamar al entrar al inicio del motorizado.
  ///
  /// Si el usuario ya había activado el seguimiento, se reanuda; si no, se
  /// queda pausado. Nunca se activa solo.
  Future<void> iniciarSiCorresponde() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      estado.value = EstadoGps.sinSesion;
      return;
    }
    _usuarioId = user.id;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefActivo) != true) {
      if (estado.value != EstadoGps.sinPermiso) estado.value = EstadoGps.apagado;
      return;
    }
    await _arrancar();
  }

  /// Activa el seguimiento (pide permiso la primera vez).
  Future<EstadoGps> activar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return estado.value = EstadoGps.sinSesion;
    _usuarioId = user.id;

    final permitido = await _permiso();
    if (!permitido) return estado.value = EstadoGps.sinPermiso;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefActivo, true);
    await _arrancar();
    return estado.value;
  }

  /// Pausa el envío y borra la última ubicación compartida.
  Future<void> desactivar() async {
    _reloj?.cancel();
    _reloj = null;
    _ultima = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefActivo, false);
    if (_usuarioId != null) await ubicacionesRepo.borrar(_usuarioId!);
    estado.value = EstadoGps.apagado;
    SyncBus.ubicacionCambio();
  }

  /// Al cerrar sesión: se corta siempre.
  Future<void> detenerPorLogout() async {
    _reloj?.cancel();
    _reloj = null;
    _ultima = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefActivo, false);
    estado.value = EstadoGps.apagado;
  }

  Future<void> _arrancar() async {
    final permitido = await _permiso();
    if (!permitido) {
      estado.value = EstadoGps.sinPermiso;
      return;
    }
    _reloj?.cancel();
    estado.value = EstadoGps.activo;
    await _enviar(primeraVez: true);
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => _enviar());
  }

  Future<bool> _permiso() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      return permiso == LocationPermission.always ||
          permiso == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<void> _enviar({bool primeraVez = false}) async {
    if (_enviando) return;
    final uid = _usuarioId;
    if (uid == null) return;
    _enviando = true;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );

      // No gastar datos si casi no se movió (salvo el primer envío).
      if (!primeraVez && _ultima != null) {
        final metros = Geolocator.distanceBetween(
          _ultima!.latitude,
          _ultima!.longitude,
          pos.latitude,
          pos.longitude,
        );
        final segundos = ultimoEnvio.value == null
            ? 999
            : DateTime.now().difference(ultimoEnvio.value!).inSeconds;
        if (metros < 25 && segundos < 120) return;
      }

      final empresaId = _empresaId ?? await _empresaDe(uid);
      if (empresaId == null) return;
      _empresaId = empresaId;

      await ubicacionesRepo.guardar(
        usuarioId: uid,
        empresaId: empresaId,
        latitud: pos.latitude,
        longitud: pos.longitude,
        precision: pos.accuracy,
      );
      _ultima = pos;
      ultimoEnvio.value = DateTime.now();
      estado.value = EstadoGps.activo;
      SyncBus.ubicacionCambio();
    } catch (_) {
      // Sin señal GPS o sin red: se reintenta en el siguiente ciclo.
    } finally {
      _enviando = false;
    }
  }

  Future<String?> _empresaDe(String uid) async {
    try {
      final p = await sb
          .from('perfiles')
          .select('empresa_id')
          .eq('id', uid)
          .maybeSingle();
      return p?['empresa_id'] as String?;
    } catch (_) {
      return null;
    }
  }
}
