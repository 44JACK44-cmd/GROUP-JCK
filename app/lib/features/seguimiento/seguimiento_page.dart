/// Seguimiento GPS de los motorizados (vista del administrador).
///
/// La frescura de cada punto es honesta: si la última actualización es vieja,
/// se dice "hace 3 min" y el marcador cambia de color. Nunca se pinta
/// "En vivo" con datos viejos.
///
/// Con clave de Google Maps se usa el mapa de Google; sin ella se mantiene el
/// mapa alternativo OSM. Las rutas reales (distancia/ETA) salen siempre del
/// servicio de Google Directions, nunca de una línea recta.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../core/config.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/sb.dart';
import '../../core/data/ubicaciones_repo.dart';
import '../../core/domain/formato.dart';
import '../../core/maps/ruta_service.dart';
import '../../core/state/bus.dart';
import '../../core/ui/aviso_maps.dart';
import '../../core/ui/widgets.dart';
import '../rutas/ruta_page.dart';

class SeguimientoPage extends ConsumerStatefulWidget {
  SeguimientoPage({super.key});

  @override
  ConsumerState<SeguimientoPage> createState() => _SeguimientoPageState();
}

class _SeguimientoPageState extends ConsumerState<SeguimientoPage> {
  final MapController _mapa = MapController();
  gmaps.GoogleMapController? _mapaGoogle;
  final RutaService _rutas = RutaService();

  List<Map<String, dynamic>> _motos = [];
  Map<String, UbicacionMotorizado> _ubicaciones = {};
  Map<String, Map<String, dynamic>> _pedidosActivos = {};
  String? _seleccionado;
  RutaResultado? _ruta;
  bool _calculandoRuta = false;
  bool _cargando = true;

  int _peticion = 0;
  Timer? _reloj;

  static const _centroInicial = LatLng(-16.4090, -71.5375); // Arequipa

  @override
  void initState() {
    super.initState();
    SyncBus.ubicaciones.addListener(_onBus);
    SyncBus.pedidos.addListener(_onBus);
    _cargar();
    // Recalcula "hace X" aunque no llegue ningún cambio.
    _reloj = Timer.periodic(Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    SyncBus.ubicaciones.removeListener(_onBus);
    SyncBus.pedidos.removeListener(_onBus);
    _reloj?.cancel();
    super.dispose();
  }

  void _onBus() {
    if (mounted) _cargar();
  }

  Future<void> _cargar() async {
    final miPeticion = ++_peticion;
    try {
      final res = await Future.wait([
        motorizadosRepo.listar(),
        ubicacionesRepo.listar(),
        sb
            .from('pedidos')
            .select(
              'id, numero, total, estado, repartidor_id, '
              'clientes(nombre, direccion, latitud, longitud)',
            )
            .inFilter('estado', ['ASIGNADO', 'EN_CAMINO'])
            .limit(300),
      ]);
      if (!mounted || miPeticion != _peticion) return;
      final activos = <String, Map<String, dynamic>>{};
      for (final p in res[2] as List) {
        final id = (p as Map)['repartidor_id'] as String?;
        if (id != null) activos[id] = Map<String, dynamic>.from(p);
      }
      setState(() {
        _motos = res[0] as List<Map<String, dynamic>>;
        _ubicaciones = {
          for (final u in res[1] as List<UbicacionMotorizado>) u.usuarioId: u,
        };
        _pedidosActivos = activos;
        _cargando = false;
      });
      if (_seleccionado != null) _calcularRuta(_seleccionado!);
    } catch (_) {
      if (!mounted || miPeticion != _peticion) return;
      setState(() => _cargando = false);
    }
  }

  Color _color(EstadoUbicacion e) => switch (e) {
        EstadoUbicacion.activo => AppTheme.success,
        EstadoUbicacion.reciente => AppTheme.warning,
        _ => AppColors.textoMuted,
      };

  LatLng get _centro {
    for (final u in _ubicaciones.values) {
      return LatLng(u.latitud, u.longitud);
    }
    return _centroInicial;
  }

  void _centrarEn(UbicacionMotorizado u) {
    setState(() {
      _seleccionado = u.usuarioId;
      _ruta = null;
    });
    try {
      _mapa.move(LatLng(u.latitud, u.longitud), 16);
    } catch (_) {}
    if (hayClaveGoogleMaps) {
      _mapaGoogle?.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(
          gmaps.LatLng(u.latitud, u.longitud),
          16,
        ),
      );
    }
    _calcularRuta(u.usuarioId);
  }

  /// Distancia y ETA reales (Google Directions) hasta el cliente del pedido
  /// activo. Sin clave o sin coordenadas no se inventa nada.
  Future<void> _calcularRuta(String motorizadoId) async {
    final ubi = _ubicaciones[motorizadoId];
    final pedido = _pedidosActivos[motorizadoId];
    if (ubi == null || pedido == null) return;
    final cliente = pedido['clientes'];
    if (cliente is! Map) return;
    final lat = (cliente['latitud'] as num?)?.toDouble();
    final lng = (cliente['longitud'] as num?)?.toDouble();
    if (lat == null || lng == null || !hayClaveGoogleMaps) return;

    if (_calculandoRuta) return;
    setState(() => _calculandoRuta = true);
    final resultado = await _rutas.calcular(
      origen: LatLng(ubi.latitud, ubi.longitud),
      destino: LatLng(lat, lng),
    );
    if (!mounted) return;
    setState(() {
      _ruta = resultado;
      _calculandoRuta = false;
    });
  }

  void _verRuta(String motorizadoId) {
    final pedido = _pedidosActivos[motorizadoId];
    if (pedido == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ese motorizado no tiene pedido activo.')),
      );
      return;
    }
    final cliente = pedido['clientes'];
    if (cliente is! Map) return;
    final lat = (cliente['latitud'] as num?)?.toDouble();
    final lng = (cliente['longitud'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('El cliente no tiene ubicación guardada.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RutaPage(
          latitud: lat,
          longitud: lng,
          clienteNombre: cliente['nombre'] as String?,
          direccion: cliente['direccion'] as String?,
        ),
      ),
    );
  }

  Widget _construirMapa() {
    if (hayClaveGoogleMaps) {
      final centro = _centro;
      return gmaps.GoogleMap(
        onMapCreated: (c) => _mapaGoogle = c,
        initialCameraPosition: gmaps.CameraPosition(
          target: gmaps.LatLng(centro.latitude, centro.longitude),
          zoom: 14,
        ),
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        markers: {
          for (final entry in _ubicaciones.entries)
            if (_motos.any((m) => m['id'] == entry.key))
              gmaps.Marker(
                markerId: gmaps.MarkerId(entry.key),
                position: gmaps.LatLng(entry.value.latitud, entry.value.longitud),
                onTap: () => _centrarEn(entry.value),
                infoWindow: gmaps.InfoWindow(
                  title: _motos
                      .firstWhere(
                        (m) => m['id'] == entry.key,
                        orElse: () => const {},
                      )['nombre'] as String? ?? 'Motorizado',
                  snippet: entry.value.haceTexto,
                ),
                icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                  entry.value.estado == EstadoUbicacion.activo
                      ? gmaps.BitmapDescriptor.hueGreen
                      : gmaps.BitmapDescriptor.hueOrange,
                ),
              ),
        },
        polylines: {
          if (_ruta != null && _ruta!.hayRuta && _ruta!.puntos.length > 1)
            gmaps.Polyline(
              polylineId: const gmaps.PolylineId('ruta-seguimiento'),
              points: _ruta!.puntos
                  .map((p) => gmaps.LatLng(p.latitude, p.longitude))
                  .toList(),
              color: AppTheme.primary,
              width: 5,
              geodesic: true,
            ),
        },
      );
    }

    return FlutterMap(
      mapController: _mapa,
      options: MapOptions(initialCenter: _centro, initialZoom: 14),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.grupojck.gas_app',
        ),
        MarkerLayer(
          markers: [
            for (final entry in _ubicaciones.entries)
              if (_motos.any((m) => m['id'] == entry.key))
                Marker(
                  point: LatLng(entry.value.latitud, entry.value.longitud),
                  width: 46,
                  height: 46,
                  child: GestureDetector(
                    onTap: () => _centrarEn(entry.value),
                    child: Icon(
                      Icons.location_on,
                      size: 46,
                      color: _color(entry.value.estado),
                      shadows: [const Shadow(color: Color(0x66000000), blurRadius: 6)],
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Motorizados en tiempo real'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      _construirMapa(),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: AvisoGoogleMaps(),
                      ),
                      Positioned(
                        left: 12,
                        top: 52,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 9, color: AppTheme.success),
                              SizedBox(width: 5),
                              Text('En vivo (< 2 min)', style: TextStyle(fontSize: 11.5)),
                              SizedBox(width: 10),
                              Icon(Icons.circle, size: 9, color: AppTheme.warning),
                              SizedBox(width: 5),
                              Text('Hace poco', style: TextStyle(fontSize: 11.5)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _lista(),
              ],
            ),
    );
  }

  Widget _lista() {
    if (_motos.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(20),
        child: EstadoVacio(
          icono: Icons.delivery_dining_outlined,
          titulo: 'No hay motorizados registrados',
        ),
      );
    }
    return Container(
      constraints: BoxConstraints(maxHeight: 290),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borde)),
      ),
      child: ListView(
        padding: EdgeInsets.symmetric(vertical: 6),
        children: [
          for (final m in _motos)
            Builder(builder: (context) {
              final id = m['id'] as String;
              final u = _ubicaciones[id];
              final estado = u?.estado ?? EstadoUbicacion.sinUbicacion;
              final nombre = m['nombre'] as String? ?? 'Motorizado';
              final pedido = _pedidosActivos[id];
              final cliente = pedido?['clientes'];
              final clienteNombre = cliente is Map ? cliente['nombre'] as String? : null;

              return ListTile(
                dense: true,
                selected: _seleccionado == id,
                leading: Icon(Icons.two_wheeler, color: _color(estado)),
                title: Text(nombre, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u == null
                          ? 'Sin ubicación compartida'
                          : '${estado.label} · ${u.haceTexto}',
                      style: TextStyle(color: _color(estado), fontSize: 12),
                    ),
                    if (pedido != null)
                      Text(
                        'Pedido #${pedido['numero']} · '
                        '${dinero((pedido['total'] as num? ?? 0).toDouble())}'
                        '${clienteNombre != null ? ' · $clienteNombre' : ''}',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textoSecundario),
                      )
                    else
                      Text('Sin pedido activo',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textoMuted)),
                    if (_seleccionado == id && _ruta != null && _ruta!.hayRuta)
                      Text(
                        'Ruta ${_ruta!.distanciaTexto} · ETA ${_ruta!.duracionTexto}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600),
                      )
                    else if (_seleccionado == id && _calculandoRuta)
                      Text('Calculando ruta…',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textoMuted)),
                  ],
                ),
                trailing: u == null
                    ? null
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _centrarEn(u),
                            child: Text('Ver'),
                          ),
                          if (pedido != null)
                            TextButton(
                              onPressed: () => _verRuta(id),
                              child: Text('Ruta'),
                            ),
                        ],
                      ),
                onTap: u == null ? null : () => _centrarEn(u),
              );
            }),
        ],
      ),
    );
  }
}