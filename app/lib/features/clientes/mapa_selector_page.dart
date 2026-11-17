/// Mini mapa para marcar la ubicación de un pedido.
///
/// Lo usa recepción al registrar el pedido (y también la ficha del cliente).
/// No es un navegador: sirve para dejar el pin en el lugar exacto en segundos.
///
/// Permite:
///  * buscar una dirección y saltar hasta ella,
///  * tocar el mapa para mover el pin,
///  * usar la ubicación actual del teléfono,
///  * escribir/corregir la dirección y una referencia ("frente al grifo").
///
/// Devuelve [UbicacionElegida] con latitud, longitud, dirección y referencia.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../core/config.dart';
import '../../core/ui/aviso_maps.dart';

/// Resultado del mini mapa.
class UbicacionElegida {
  final double latitud;
  final double longitud;
  final String? direccion;
  final String? referencia;

  UbicacionElegida({
    required this.latitud,
    required this.longitud,
    this.direccion,
    this.referencia,
  });
}

/// Abre el mini mapa y espera la confirmación del usuario.
Future<UbicacionElegida?> abrirMiniMapa(
  BuildContext context, {
  double? latitud,
  double? longitud,
  String? direccion,
  String? referencia,
  String titulo = 'Ubicación del pedido',
}) {
  return Navigator.of(context).push<UbicacionElegida>(
    MaterialPageRoute(
      builder: (_) => MapaSelectorPage(
        latitud: latitud,
        longitud: longitud,
        direccion: direccion,
        referencia: referencia,
        titulo: titulo,
      ),
    ),
  );
}

class MapaSelectorPage extends StatefulWidget {
  final double? latitud;
  final double? longitud;
  final String? direccion;
  final String? referencia;
  final String? titulo;

  MapaSelectorPage({
    super.key,
    this.latitud,
    this.longitud,
    this.direccion,
    this.referencia,
    this.titulo,
  });

  @override
  State<MapaSelectorPage> createState() => _MapaSelectorPageState();
}

class _MapaSelectorPageState extends State<MapaSelectorPage> {
  static const _userAgent = 'GasApp/1.0 (com.grupojck.gas_app)';

  late LatLng _posicion;
  final MapController _controlador = MapController();
  gmaps.GoogleMapController? _mapaGoogle;
  final _busquedaCtrl = TextEditingController();
  late final TextEditingController _direccionCtrl =
      TextEditingController(text: widget.direccion ?? '');
  late final TextEditingController _referenciaCtrl =
      TextEditingController(text: widget.referencia ?? '');

  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  bool _ubicando = false;
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    _posicion = LatLng(
      widget.latitud ?? -16.4090, // Arequipa como referencia inicial
      widget.longitud ?? -71.5375,
    );
  }

  @override
  void dispose() {
    _espera?.cancel();
    _busquedaCtrl.dispose();
    _direccionCtrl.dispose();
    _referenciaCtrl.dispose();
    super.dispose();
  }

  /// Google Maps nativo cuando hay clave; si no, el mapa OSM de siempre.
  /// La selección de ubicación funciona igual en ambos.
  Widget _mapa() {
    if (hayClaveGoogleMaps) {
      return gmaps.GoogleMap(
        onMapCreated: (c) => _mapaGoogle = c,
        initialCameraPosition: gmaps.CameraPosition(
          target: gmaps.LatLng(_posicion.latitude, _posicion.longitude),
          zoom: 16,
        ),
        onTap: (punto) => setState(() => _posicion = LatLng(
              punto.latitude,
              punto.longitude,
            )),
        markers: {
          gmaps.Marker(
            markerId: const gmaps.MarkerId('destino'),
            position: gmaps.LatLng(_posicion.latitude, _posicion.longitude),
            infoWindow: const gmaps.InfoWindow(title: 'Ubicación elegida'),
            icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              gmaps.BitmapDescriptor.hueRed,
            ),
          ),
        },
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
      );
    }

    return FlutterMap(
      mapController: _controlador,
      options: MapOptions(
        initialCenter: _posicion,
        initialZoom: 16,
        onTap: (_, point) => setState(() => _posicion = point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.grupojck.gas_app',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _posicion,
              width: 48,
              height: 48,
              child: Icon(
                Icons.location_on,
                size: 48,
                color: AppTheme.danger,
                shadows: [Shadow(color: AppColors.textoMuted, blurRadius: 6)],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _moverA(LatLng punto) {
    setState(() => _posicion = punto);
    _controlador.move(punto, 17);
    _mapaGoogle?.animateCamera(
      gmaps.CameraUpdate.newLatLngZoom(
        gmaps.LatLng(punto.latitude, punto.longitude),
        17,
      ),
    );
  }

  /// Búsqueda de direcciones con OpenStreetMap (no necesita clave).
  Future<void> _buscar(String texto) async {
    _espera?.cancel();
    final q = texto.trim();
    if (q.length < 3) {
      setState(() => _resultados = []);
      return;
    }
    _espera = Timer(Duration(milliseconds: 550), () async {
      setState(() => _buscando = true);
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?format=jsonv2&addressdetails=0&limit=6&countrycodes=pe'
          '&q=${Uri.encodeQueryComponent(q)}',
        );
        final r = await http
            .get(uri, headers: {'User-Agent': _userAgent})
            .timeout(Duration(seconds: 10));
        if (!mounted) return;
        if (r.statusCode == 200) {
          final data = jsonDecode(r.body) as List;
          setState(() {
            _resultados = data.cast<Map<String, dynamic>>();
            _buscando = false;
          });
        } else {
          setState(() {
            _resultados = [];
            _buscando = false;
          });
        }
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _resultados = [];
          _buscando = false;
        });
      }
    });
  }

  void _elegirResultado(Map<String, dynamic> r) {
    final lat = double.tryParse('${r['lat']}');
    final lng = double.tryParse('${r['lon']}');
    if (lat == null || lng == null) return;
    setState(() {
      _resultados = [];
      _busquedaCtrl.clear();
      if (_direccionCtrl.text.trim().isEmpty) {
        _direccionCtrl.text = (r['display_name'] as String? ?? '').split(',').take(3).join(',').trim();
      }
    });
    FocusScope.of(context).unfocus();
    _moverA(LatLng(lat, lng));
  }

  Future<void> _usarMiUbicacion() async {
    setState(() => _ubicando = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _aviso('Activa el GPS del teléfono para usar tu ubicación.');
        return;
      }
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        _aviso('Falta el permiso de ubicación. Puedes activarlo en Configuración.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(Duration(seconds: 15));
      if (!mounted) return;
      _moverA(LatLng(p.latitude, p.longitude));
      if (_direccionCtrl.text.trim().isEmpty) {
        await _direccionDesdeCoordenadas(p.latitude, p.longitude);
      }
    } on TimeoutException {
      _aviso('El GPS tardó demasiado. Marca el punto tocando el mapa.');
    } catch (_) {
      _aviso('No se pudo obtener tu ubicación. Marca el punto tocando el mapa.');
    } finally {
      if (mounted) setState(() => _ubicando = false);
    }
  }

  /// Rellena la dirección a partir del pin (OpenStreetMap inverso).
  Future<void> _direccionDesdeCoordenadas(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2&zoom=18&addressdetails=0&lat=$lat&lon=$lng',
      );
      final r = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(Duration(seconds: 8));
      if (!mounted || r.statusCode != 200) return;
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final texto = (data['display_name'] as String? ?? '').split(',').take(3).join(',').trim();
      if (texto.isNotEmpty && _direccionCtrl.text.trim().isEmpty) {
        setState(() => _direccionCtrl.text = texto);
      }
    } catch (_) {
      // Sin dirección automática: el usuario puede escribirla.
    }
  }

  void _confirmar() {
    Navigator.of(context).pop(UbicacionElegida(
      latitud: _posicion.latitude,
      longitud: _posicion.longitude,
      direccion: _direccionCtrl.text.trim().isEmpty ? null : _direccionCtrl.text.trim(),
      referencia: _referenciaCtrl.text.trim().isEmpty ? null : _referenciaCtrl.text.trim(),
    ));
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo ?? 'Ubicación del pedido'),
        actions: [
          TextButton(
            onPressed: _confirmar,
            child: Text('Listo'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _busquedaCtrl,
              textInputAction: TextInputAction.search,
              onChanged: _buscar,
              onSubmitted: _buscar,
              decoration: InputDecoration(
                hintText: 'Buscar dirección (Av. Ejército 123)',
                prefixIcon: Icon(Icons.search),
                suffixIcon: _buscando
                    ? Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                isDense: true,
              ),
            ),
          ),
          if (_resultados.isNotEmpty)
            Container(
              margin: EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borde),
              ),
              child: Column(
                children: [
                  for (final r in _resultados.take(4))
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.place_outlined, size: 20),
                      title: Text(
                        '${r['display_name']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13),
                      ),
                      onTap: () => _elegirResultado(r),
                    ),
                ],
              ),
            ),
          AvisoGoogleMaps(),
          Expanded(
            child: Stack(
              children: [
                _mapa(),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'mi-ubicacion',
                    onPressed: _ubicando ? null : _usarMiUbicacion,
                    backgroundColor: AppColors.superficie,
                    child: _ubicando
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.my_location, color: AppTheme.primary),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Toca el mapa para mover el pin',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textoSecundario),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.borde)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _direccionCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Dirección',
                      hintText: 'Av. Ejército 123',
                      prefixIcon: Icon(Icons.signpost_outlined),
                      isDense: true,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _referenciaCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Referencia (opcional)',
                      hintText: 'Frente al grifo, casa azul…',
                      prefixIcon: Icon(Icons.info_outline),
                      isDense: true,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '${_posicion.latitude.toStringAsFixed(6)}, ${_posicion.longitude.toStringAsFixed(6)}',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textoMuted),
                  ),
                  SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _confirmar,
                    icon: Icon(Icons.check),
                    label: Text('Confirmar ubicación'),
                    style: FilledButton.styleFrom(minimumSize: Size.fromHeight(50)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}