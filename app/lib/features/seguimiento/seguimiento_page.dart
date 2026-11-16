/// Seguimiento GPS de los motorizados (vista del administrador).
///
/// La frescura de cada punto es honesta: si la última actualización es vieja,
/// se dice "Sin actualizar" y el marcador cambia de color. Nunca se pinta
/// "en vivo" con datos viejos.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/sb.dart';
import '../../core/data/ubicaciones_repo.dart';
import '../../core/state/bus.dart';
import '../../core/ui/widgets.dart';

class SeguimientoPage extends ConsumerStatefulWidget {
  const SeguimientoPage({super.key});

  @override
  ConsumerState<SeguimientoPage> createState() => _SeguimientoPageState();
}

class _SeguimientoPageState extends ConsumerState<SeguimientoPage> {
  final MapController _mapa = MapController();

  List<Map<String, dynamic>> _motos = [];
  Map<String, UbicacionMotorizado> _ubicaciones = {};
  String? _seleccionado;
  bool _cargando = true;

  int _peticion = 0;
  RealtimeChannel? _canal;
  Timer? _reloj;

  static const _centroInicial = LatLng(-16.4090, -71.5375); // Arequipa

  @override
  void initState() {
    super.initState();
    SyncBus.ubicaciones.addListener(_onBus);
    _cargar();
    _escuchar();
    // Recalcula "hace X" aunque no llegue ningún cambio.
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    SyncBus.ubicaciones.removeListener(_onBus);
    _reloj?.cancel();
    _canal?.unsubscribe();
    super.dispose();
  }

  void _onBus() {
    if (mounted) _cargar();
  }

  void _escuchar() {
    try {
      _canal = sb
          .channel('seguimiento-admin')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'ubicaciones_motorizado',
            callback: (_) {
              if (mounted) _cargar();
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _cargar() async {
    final miPeticion = ++_peticion;
    try {
      final res = await Future.wait([
        motorizadosRepo.listar(),
        ubicacionesRepo.listar(),
      ]);
      if (!mounted || miPeticion != _peticion) return;
      setState(() {
        _motos = res[0] as List<Map<String, dynamic>>;
        _ubicaciones = {
          for (final u in res[1] as List<UbicacionMotorizado>) u.usuarioId: u,
        };
        _cargando = false;
      });
    } catch (_) {
      if (!mounted || miPeticion != _peticion) return;
      setState(() => _cargando = false);
    }
  }

  Color _color(EstadoUbicacion e) => switch (e) {
        EstadoUbicacion.activo => AppTheme.success,
        EstadoUbicacion.reciente => AppTheme.warning,
        _ => Colors.black38,
      };

  LatLng get _centro {
    for (final u in _ubicaciones.values) {
      return LatLng(u.latitud, u.longitud);
    }
    return _centroInicial;
  }

  void _centrarEn(UbicacionMotorizado u) {
    setState(() => _seleccionado = u.usuarioId);
    try {
      _mapa.move(LatLng(u.latitud, u.longitud), 16);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguimiento GPS'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapa,
                        options: MapOptions(
                          initialCenter: _centro,
                          initialZoom: 14,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.grupojck.gas_app',
                          ),
                          MarkerLayer(
                            markers: [
                              for (final entry in _ubicaciones.entries)
                                if (_motos.any((m) => m['id'] == entry.key))
                                  Marker(
                                    point: LatLng(
                                      entry.value.latitud,
                                      entry.value.longitud,
                                    ),
                                    width: 46,
                                    height: 46,
                                    child: GestureDetector(
                                      onTap: () => _centrarEn(entry.value),
                                      child: Icon(
                                        Icons.location_on,
                                        size: 46,
                                        color: _color(entry.value.estado),
                                        shadows: const [
                                          Shadow(color: Colors.black26, blurRadius: 6),
                                        ],
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 9, color: AppTheme.success),
                              SizedBox(width: 5),
                              Text('En vivo (< 2 min)',
                                  style: TextStyle(fontSize: 11.5)),
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
      return const Padding(
        padding: EdgeInsets.all(20),
        child: EstadoVacio(
          icono: Icons.delivery_dining_outlined,
          titulo: 'No hay motorizados registrados',
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE6E8E5))),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          for (final m in _motos)
            Builder(builder: (context) {
              final id = m['id'] as String;
              final u = _ubicaciones[id];
              final estado = u?.estado ?? EstadoUbicacion.sinUbicacion;
              final nombre = m['nombre'] as String? ?? 'Motorizado';
              return ListTile(
                dense: true,
                selected: _seleccionado == id,
                leading: Icon(Icons.location_on, color: _color(estado)),
                title: Text(nombre,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  u == null
                      ? 'Sin ubicación compartida'
                      : '${estado.label} · ${u.haceTexto}',
                  style: TextStyle(color: _color(estado), fontSize: 12),
                ),
                trailing: u == null
                    ? null
                    : TextButton(
                        onPressed: () => _centrarEn(u),
                        child: const Text('Ver'),
                      ),
              );
            }),
        ],
      ),
    );
  }
}
