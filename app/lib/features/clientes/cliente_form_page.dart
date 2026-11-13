import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_controller.dart';

/// Formulario para crear o editar un cliente.
/// Devuelve true al Navigator.pop si se guardó correctamente.
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
  late final TextEditingController _lat;
  late final TextEditingController _lng;

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
    _lat = TextEditingController(
        text: c?['latitud']?.toString() ?? '');
    _lng = TextEditingController(
        text: c?['longitud']?.toString() ?? '');
    _tipo = c?['tipo'] as String? ?? 'PARTICULAR';
    _activo = c?['activo'] as bool? ?? true;
  }

  @override
  void dispose() {
    for (final c in [_nombre, _telefono, _direccion, _referencia, _observaciones, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

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
        _lat.text = pos.latitude.toStringAsFixed(7);
        _lng.text = pos.longitude.toStringAsFixed(7);
      });
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

    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if ((_lat.text.trim().isEmpty) != (_lng.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La latitud y longitud deben ir juntas.')),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      final sb = Supabase.instance.client;
      final datos = {
        'nombre': _nombre.text.trim(),
        'telefono': _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
        'tipo': _tipo,
        'direccion': _direccion.text.trim().isEmpty ? null : _direccion.text.trim(),
        'referencia': _referencia.text.trim().isEmpty ? null : _referencia.text.trim(),
        'observaciones': _observaciones.text.trim().isEmpty ? null : _observaciones.text.trim(),
        'latitud': lat,
        'longitud': lng,
      };

      if (_esEdicion) {
        await sb.from('clientes').update({...datos, 'activo': _activo}).eq('id', widget.cliente!['id']);
      } else {
        await sb.from('clientes').insert({
          ...datos,
          'empresa_id': ref.read(authProvider).empresaId,
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar. Revisa tu conexión e inténtalo de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
              decoration: const InputDecoration(labelText: 'Nombre *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _telefono,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo de cliente'),
              items: [
                for (final e in _tipos.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _tipo = v ?? 'PARTICULAR'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _direccion,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Dirección'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _referencia,
              decoration: const InputDecoration(
                labelText: 'Referencia',
                hintText: 'Ej. Portón verde, frente a la cancha',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Latitud'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Longitud'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _obteniendoGps ? null : _usarMiUbicacion,
              icon: _obteniendoGps
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: const Text('Usar mi ubicación actual'),
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
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 22, width: 22,
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
