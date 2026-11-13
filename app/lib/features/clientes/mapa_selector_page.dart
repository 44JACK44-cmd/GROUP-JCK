/// Selector de ubicación en el mapa.
///
/// El ADMIN mueve el marcador hasta el punto exacto donde queda el cliente
/// y guarda esas coordenadas. La ubicación que se guarda es la del CLIENTE,
/// no la del teléfono de quien registra.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';

class MapaSelectorPage extends StatefulWidget {
  final double? latitud;
  final double? longitud;
  final String? titulo;

  const MapaSelectorPage({
    super.key,
    this.latitud,
    this.longitud,
    this.titulo,
  });

  @override
  State<MapaSelectorPage> createState() => _MapaSelectorPageState();
}

class _MapaSelectorPageState extends State<MapaSelectorPage> {
  late LatLng _posicion;
  final MapController _controlador = MapController();

  @override
  void initState() {
    super.initState();
    _posicion = LatLng(
      widget.latitud ?? -16.4090, // Arequipa (referencia)
      widget.longitud ?? -71.5375,
    );
  }

  void _guardar() {
    Navigator.of(context).pop({
      'latitud': _posicion.latitude,
      'longitud': _posicion.longitude,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo ?? 'Ubicación del cliente'),
        actions: [
          TextButton(
            onPressed: _guardar,
            child: const Text('Guardar'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controlador,
            options: MapOptions(
              initialCenter: _posicion,
              initialZoom: 16,
              onTap: (_, point) => setState(() => _posicion = point),
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) setState(() => _posicion = position.center);
              },
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
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.location_on,
                      size: 44,
                      color: AppTheme.danger,
                      shadows: [Shadow(color: Colors.black26, blurRadius: 6)],
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Instruction + coordinates
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Toca el mapa o arrastra el marcador hasta el lugar exacto del cliente.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_posicion.latitude.toStringAsFixed(6)}, ${_posicion.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _guardar,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.check),
        label: const Text('Guardar ubicación'),
      ),
    );
  }
}
