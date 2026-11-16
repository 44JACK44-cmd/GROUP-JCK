/// Navegación en la app hasta el cliente.
///
/// * Con clave de Google Maps: mapa de Google + recorrido real (Directions) y
///   asistente de voz en español con las indicaciones reales.
/// * Sin clave: mapa alternativo (OpenStreetMap) con un aviso claro y un botón
///   para abrir la ruta en Google Maps.
///
/// El destino SIEMPRE es la ubicación guardada del cliente. La ubicación del
/// teléfono solo indica dónde está el motorizado.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_tts/flutter_tts.dart' show FlutterTts;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../core/audio/voz_service.dart';
import '../../core/config.dart';
import '../../core/domain/navegacion.dart';
import '../../core/maps/ruta_service.dart';
import '../../core/ui/aviso_maps.dart';

class RutaPage extends StatefulWidget {
  final double latitud;
  final double longitud;
  final String? clienteNombre;
  final String? direccion;

  const RutaPage({
    super.key,
    required this.latitud,
    required this.longitud,
    this.clienteNombre,
    this.direccion,
  });

  @override
  State<RutaPage> createState() => _RutaPageState();
}

class _RutaPageState extends State<RutaPage> {
  gmaps.GoogleMapController? _mapaGoogle;
  final fm.MapController _mapaAlterno = fm.MapController();
  final RutaService _rutas = const RutaService();
  final VozService _voz = VozService.instance;

  StreamSubscription<Position>? _seguimiento;
  Timer? _esperaMapa;

  bool _cargandoUbicacion = true;
  String? _errorUbicacion;
  Position? _posicion;

  bool _cargandoRuta = false;
  RutaResultado? _ruta;

  int _pasoActual = -1;
  int _ultimoAnunciado = -1;
  bool _vozActiva = false;
  LatLng? _ultimoPuntoAnuncio;

  LatLng get _destino => LatLng(widget.latitud, widget.longitud);

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _seguimiento?.cancel();
    _esperaMapa?.cancel();
    _voz.detener();
    super.dispose();
  }

  // ---------------------------------------------------------------- datos

  Future<void> _iniciar() async {
    await _obtenerUbicacion();
    if (!mounted) return;
    if (_posicion == null) {
      // Sin ubicación actual no se puede pedir una ruta: se deja claro.
      setState(() {
        _cargandoRuta = false;
        _ruta = RutaResultado(
          destino: _destino,
          error: _errorUbicacion ??
              'No se pudo obtener tu ubicación. Activa el GPS para navegar.',
        );
      });
      return;
    }
    await _calcularRuta();
    _seguirUbicacion();
    _vozActiva = await _voz.disponible();
    if (mounted) setState(() {});
  }

  Future<void> _obtenerUbicacion() async {
    setState(() {
      _cargandoUbicacion = true;
      _errorUbicacion = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _errorUbicacion = 'El GPS está apagado. Actívalo para navegar.';
        return;
      }
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied) {
        _errorUbicacion = 'Falta permiso de ubicación para calcular la ruta.';
        return;
      }
      if (permiso == LocationPermission.deniedForever) {
        _errorUbicacion =
            'El permiso de ubicación está bloqueado. Actívalo en los ajustes del teléfono.';
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _posicion = pos;
    } on TimeoutException {
      _errorUbicacion = 'El GPS tardó demasiado en ubicarte. Inténtalo de nuevo.';
      // Se intenta con la última posición conocida, si existe.
      _posicion = await Geolocator.getLastKnownPosition();
    } catch (_) {
      _posicion = await Geolocator.getLastKnownPosition();
      if (_posicion == null) {
        _errorUbicacion = 'No se pudo obtener tu ubicación.';
      }
    } finally {
      _cargandoUbicacion = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _calcularRuta() async {
    final pos = _posicion;
    if (pos == null) return;
    setState(() => _cargandoRuta = true);
    final resultado = await _rutas.calcular(
      origen: LatLng(pos.latitude, pos.longitude),
      destino: _destino,
    );
    if (!mounted) return;
    setState(() {
      _ruta = resultado;
      _cargandoRuta = false;
      _pasoActual = resultado.instrucciones.isEmpty ? -1 : 0;
      _ultimoAnunciado = _pasoActual;
    });
    if (resultado.hayRuta) {
      _encuadrarRuta();
    }
  }

  void _encuadrarRuta() {
    final puntos = _ruta?.puntos ?? const <LatLng>[];
    if (puntos.isEmpty) return;
    if (hayClaveGoogleMaps) {
      _esperaMapa?.cancel();
      _esperaMapa = Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        final latitudes = [...puntos.map((p) => p.latitude), widget.latitud];
        final longitudes = [...puntos.map((p) => p.longitude), widget.longitud];
        final limites = gmaps.LatLngBounds(
          southwest: gmaps.LatLng(
            latitudes.reduce((a, b) => a < b ? a : b),
            longitudes.reduce((a, b) => a < b ? a : b),
          ),
          northeast: gmaps.LatLng(
            latitudes.reduce((a, b) => a > b ? a : b),
            longitudes.reduce((a, b) => a > b ? a : b),
          ),
        );
        _mapaGoogle?.moveCamera(gmaps.CameraUpdate.newLatLngBounds(limites, 48));
      });
    } else {
      _mapaAlterno.fitCamera(
        fm.CameraFit.bounds(
          bounds: fm.LatLngBounds.fromPoints(
            puntos.map((p) => LatLng(p.latitude, p.longitude)).toList(),
          ),
          padding: const EdgeInsets.all(48),
        ),
      );
    }
  }

  void _seguirUbicacion() {
    _seguimiento?.cancel();
    _seguimiento = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _posicion = pos);
      final ruta = _ruta;
      if (ruta == null || ruta.instrucciones.isEmpty) return;
      final indice = ruta.indiceCercano(LatLng(pos.latitude, pos.longitude));
      if (indice != _pasoActual) {
        setState(() => _pasoActual = indice);
      }
      _anunciarSiCorresponde(indice, LatLng(pos.latitude, pos.longitude));
    }, onError: (_) {});
  }

  void _anunciarSiCorresponde(int indice, LatLng posicion) {
    if (!_vozActiva) return;
    if (indice < 0 || indice >= (_ruta?.instrucciones.length ?? 0)) return;
    if (indice == _ultimoAnunciado && _ultimoPuntoAnuncio != null) {
      const medidor = Distance();
      if (medidor(_ultimoPuntoAnuncio!, posicion) < 120) return;
    }
    _ultimoAnunciado = indice;
    _ultimoPuntoAnuncio = posicion;
    _voz.hablar(_ruta!.instrucciones[indice].paraVoz);
  }

  Future<void> _escucharAhora() async {
    final ruta = _ruta;
    if (ruta == null || ruta.instrucciones.isEmpty) return;
    final indice = _pasoActual >= 0
        ? _pasoActual
        : ruta.indiceCercano(
            _posicion == null
                ? null
                : LatLng(_posicion!.latitude, _posicion!.longitude),
          );
    if (indice < 0) return;
    setState(() {
      _pasoActual = indice;
      _ultimoAnunciado = indice;
      _ultimoPuntoAnuncio = _posicion == null
          ? null
          : LatLng(_posicion!.latitude, _posicion!.longitude);
    });
    await _voz.hablar(ruta.instrucciones[indice].paraVoz);
  }

  Future<void> _abrirGoogleMaps() async {
    await navegarACliente(
      latitud: widget.latitud,
      longitud: widget.longitud,
      direccion: widget.direccion,
    );
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final titulo = widget.clienteNombre?.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(titulo == null || titulo.isEmpty ? 'Ruta al cliente' : titulo),
        actions: [
          IconButton(
            tooltip: 'Abrir en Google Maps',
            onPressed: _abrirGoogleMaps,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: Stack(
        children: [
          _mapa(),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AvisoGoogleMaps(),
          ),
          if (_cargandoUbicacion || _cargandoRuta)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          Positioned(left: 12, right: 12, top: 12, child: _aviso()),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _panel(),
          ),
        ],
      ),
    );
  }

  Widget _mapa() {
    final ruta = _ruta;
    final puntos = ruta?.puntos ?? const <LatLng>[];
    final miPosicion = _posicion;

    if (hayClaveGoogleMaps) {
      final centro = miPosicion != null
          ? gmaps.LatLng(miPosicion.latitude, miPosicion.longitude)
          : gmaps.LatLng(widget.latitud, widget.longitud);
      return gmaps.GoogleMap(
        onMapCreated: (controlador) => _mapaGoogle = controlador,
        initialCameraPosition: gmaps.CameraPosition(target: centro, zoom: 15),
        myLocationEnabled: miPosicion != null,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        markers: {
          gmaps.Marker(
            markerId: const gmaps.MarkerId('cliente'),
            position: gmaps.LatLng(widget.latitud, widget.longitud),
            infoWindow: gmaps.InfoWindow(
              title: widget.clienteNombre ?? 'Cliente',
              snippet: widget.direccion,
            ),
            icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              gmaps.BitmapDescriptor.hueRed,
            ),
          ),
        },
        polylines: {
          if (puntos.length > 1)
            gmaps.Polyline(
              polylineId: const gmaps.PolylineId('ruta'),
              points: puntos
                  .map((p) => gmaps.LatLng(p.latitude, p.longitude))
                  .toList(),
              color: AppTheme.primary,
              width: 6,
              geodesic: true,
            ),
        },
      );
    }

    // Mapa alternativo: no dibuja una ruta falsa, solo los puntos reales.
    final centro = miPosicion != null
        ? LatLng(miPosicion.latitude, miPosicion.longitude)
        : LatLng(widget.latitud, widget.longitud);
    return fm.FlutterMap(
      mapController: _mapaAlterno,
      options: fm.MapOptions(initialCenter: centro, initialZoom: 15),
      children: [
        fm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.grupojck.gas_app',
        ),
        fm.MarkerLayer(
          markers: [
            fm.Marker(
              point: LatLng(widget.latitud, widget.longitud),
              width: 46,
              height: 46,
              child: const Icon(
                Icons.location_on,
                size: 46,
                color: AppTheme.danger,
                shadows: [Shadow(color: Colors.black26, blurRadius: 6)],
              ),
            ),
            if (miPosicion != null)
              fm.Marker(
                point: LatLng(miPosicion.latitude, miPosicion.longitude),
                width: 30,
                height: 30,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _aviso() {
    final ruta = _ruta;
    final error = ruta?.error;
    if (error == null) return const SizedBox.shrink();
    return Card(
      color: const Color(0xFFFFF8E1),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: AppTheme.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              hayClaveGoogleMaps
                  ? 'Puedes abrir la ruta en Google Maps con el botón de arriba.'
                  : 'Esta compilación no tiene clave de Google Maps: el mapa '
                      'alternativo no calcula el recorrido. Abre la ruta en '
                      'Google Maps con el botón de arriba.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel() {
    final ruta = _ruta;
    if (ruta == null) return const SizedBox.shrink();

    final instrucciones = ruta.instrucciones;
    final paso = _pasoActual >= 0 && _pasoActual < instrucciones.length
        ? instrucciones[_pasoActual]
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ruta.hayRuta) ...[
              Row(
                children: [
                  const Icon(Icons.route, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    [
                      if (ruta.distanciaTexto.isNotEmpty) ruta.distanciaTexto,
                      if (ruta.duracionTexto.isNotEmpty) ruta.duracionTexto,
                    ].join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (_vozActiva)
                    const Icon(Icons.volume_up_outlined,
                        size: 18, color: AppTheme.primary),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (paso != null) ...[
              Text(
                paso.texto,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'En ${paso.distanciaTexto}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 10),
            ] else if (ruta.hayRuta)
              const Text(
                'El recorrido no trae indicaciones. Sigue la línea de la ruta.',
                style: TextStyle(color: Colors.black54),
              ),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: paso == null ? null : _escucharAhora,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Escuchar'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _abrirGoogleMaps,
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Abrir en Google Maps'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Comprueba si el teléfono puede hablar (se usa en Ajustes).
Future<bool> vozDisponibleEnTelefono() async {
  try {
    final tts = FlutterTts();
    final ok = await tts.setLanguage('es-PE');
    return ok == 1 || await tts.setLanguage('es-ES') == 1;
  } catch (_) {
    return false;
  }
}
