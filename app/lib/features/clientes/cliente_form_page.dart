/// Formulario para crear o editar un cliente.
///
/// La dirección del cliente se guarda con su referencia y sus coordenadas.
/// Las coordenadas se eligen en el mapa: la ubicación del teléfono NO se
/// usa como ubicación del cliente (solo como ayuda para el punto actual).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/theme.dart';
import '../../core/data/clientes_repo.dart';
import '../../core/data/sb.dart';
import '../auth/auth_controller.dart';
import 'mapa_selector_page.dart';

class ClienteFormPage extends ConsumerStatefulWidget {
  final Map<String, dynamic>? cliente;

  const ClienteFormPage({super.key, this.cliente});

  @override
  ConsumerState<ClienteFormPage> createState() => _ClienteFormPageState();
}

class _ClienteFormPageState extends ConsumerState<ClienteFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _telefono;
  late final TextEditingController _direccion;
  late final TextEditingController _referencia;
  late final TextEditingController _observaciones;

  double? _latitud;
  double? _longitud;
  String _tipo = 'PARTICULAR';
  bool _activo = true;
  bool _guardando = false;
  bool _obteniendoGps = false;

  bool get _esEdicion => widget.cliente != null;

  static const _tipos = {
    'PARTICULAR': 'Particular',
    'RESTAURANTE': 'Restaurante',
    'NEGOCIO': 'Negocio',
    'OTRO': 'Otro',
  };

  @override
  void initState() {
    super.initState();
    final c = widget.cliente;
    _nombre = TextEditingController(text: c?['nombre'] as String? ?? '');
    _telefono = TextEditingController(text: c?['telefono'] as String? ?? '');
    _direccion = TextEditingController(text: c?['direccion'] as String? ?? '');
    _referencia = TextEditingController(text: c?['referencia'] as String? ?? '');
    _observaciones = TextEditingController(text: c?['observaciones'] as String? ?? '');
    _latitud = (c?['latitud'] as num?)?.toDouble();
    _longitud = (c?['longitud'] as num?)?.toDouble();
    _tipo = c?['tipo'] as String? ?? 'PARTICULAR';
    _activo = c?['activo'] as bool? ?? true;
  }

  @override
  void dispose() {
    for (final c in [_nombre, _telefono, _direccion, _referencia, _observaciones]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Abre el mapa para elegir el punto del cliente.
  Future<void> _elegirEnMapa() async {
    final resultado = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => MapaSelectorPage(
          latitud: _latitud,
          longitud: _longitud,
          titulo: 'Ubicación de ${_nombre.text.trim().isEmpty ? 'el cliente' : _nombre.text.trim()}',
        ),
      ),
    );
    if (resultado == null) return;
    setState(() {
      _latitud = resultado['latitud'] as double?;
      _longitud = resultado['longitud'] as double?;
    });
  }

  /// Toma el punto actual del teléfono como ayuda (queda marcado como
  /// "punto actual", el admin debe confirmar la ubicación del cliente).
  Future<void> _usarMiUbicacion() async {
    setState(() => _obteniendoGps = true);
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Necesitamos permiso de ubicación para marcar el punto.')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _latitud = pos.latitude;
        _longitud = pos.longitude;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Punto actual marcado. Ajústalo en el mapa si hace falta.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos obtener tu ubicación. Inténtalo de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _obteniendoGps = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);
    final auth = ref.read(authProvider);
    try {
      if (_esEdicion) {
        await clientesRepo.actualizar(
          clienteId: widget.cliente!['id'] as String,
          nombre: _nombre.text.trim(),
          telefono: _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
          tipo: _tipo,
          direccion: _direccion.text.trim().isEmpty ? null : _direccion.text.trim(),
          referencia: _referencia.text.trim().isEmpty ? null : _referencia.text.trim(),
          latitud: _latitud,
          longitud: _longitud,
          observaciones: _observaciones.text.trim().isEmpty ? null : _observaciones.text.trim(),
          activo: _activo,
        );
      } else {
        await clientesRepo.crear(
          empresaId: auth.empresaId!,
          nombre: _nombre.text.trim(),
          telefono: _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
          tipo: _tipo,
          direccion: _direccion.text.trim().isEmpty ? null : _direccion.text.trim(),
          referencia: _referencia.text.trim().isEmpty ? null : _referencia.text.trim(),
          latitud: _latitud,
          longitud: _longitud,
          observaciones: _observaciones.text.trim().isEmpty ? null : _observaciones.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos guardar el cliente').mensaje)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tieneUbicacion = _latitud != null && _longitud != null;
    return Scaffold(
      appBar: AppBar(title: Text(_esEdicion ? 'Editar cliente' : 'Nuevo cliente')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre *', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _telefono,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo de cliente', prefixIcon: Icon(Icons.category_outlined)),
              items: [
                for (final e in _tipos.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _tipo = v ?? 'PARTICULAR'),
            ),
            const SizedBox(height: 18),
            Text('Dirección de entrega',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _direccion,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Dirección',
                hintText: 'Ej. Av. Ejército 123',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _referencia,
              decoration: const InputDecoration(
                labelText: 'Referencia',
                hintText: 'Ej. A dos cuadras del parque',
                prefixIcon: Icon(Icons.signpost_outlined),
              ),
            ),
            const SizedBox(height: 14),
            // --- Ubicación ---
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          tieneUbicacion ? Icons.location_on : Icons.location_off_outlined,
                          color: tieneUbicacion ? AppTheme.success : Colors.black45,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tieneUbicacion ? 'Ubicación guardada' : 'Sin ubicación',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    if (tieneUbicacion)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 28),
                        child: Text(
                          '${_latitud!.toStringAsFixed(6)}, ${_longitud!.toStringAsFixed(6)}',
                          style: const TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _elegirEnMapa,
                        icon: const Icon(Icons.map_outlined),
                        label: Text(tieneUbicacion ? 'Cambiar en el mapa' : 'Elegir en el mapa'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _obteniendoGps ? null : _usarMiUbicacion,
                        icon: _obteniendoGps
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location),
                        label: const Text('Usar el punto actual (ajústalo después)'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _observaciones,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Observaciones'),
            ),
            if (_esEdicion) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cliente activo'),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _guardando
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_esEdicion ? 'Guardar cambios' : 'Guardar cliente'),
            ),
          ],
        ),
      ),
    );
  }
}
