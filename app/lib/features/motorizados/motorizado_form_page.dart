import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';

/// Formulario para crear o editar un motorizado.
/// - Crear → Edge Function `create-motorizado`
/// - Editar → Edge Function `update-motorizado`
class MotorizadoFormPage extends StatefulWidget {
  final Map<String, dynamic>? motorizado;
  final List<Map<String, dynamic>> vehiculos;

  const MotorizadoFormPage({super.key, this.motorizado, required this.vehiculos});

  @override
  State<MotorizadoFormPage> createState() => _MotorizadoFormPageState();
}

class _MotorizadoFormPageState extends State<MotorizadoFormPage> {
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String? _vehiculoId;
  bool _activo = true;
  bool _cargando = false;
  String? _error;

  bool get _esEdicion => widget.motorizado != null;

  @override
  void initState() {
    super.initState();
    final m = widget.motorizado;
    if (m != null) {
      _nombreCtrl.text = m['nombre'] as String? ?? '';
      _telefonoCtrl.text = m['telefono'] as String? ?? '';
      _activo = m['activo'] as bool? ?? true;
      // Vehículo actual
      for (final v in widget.vehiculos) {
        if (v['repartidor_id'] == m['id']) _vehiculoId = v['id'] as String?;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_nombreCtrl, _telefonoCtrl, _correoCtrl, _passwordCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final telefono = _telefonoCtrl.text.trim();
    final correo = _correoCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (nombre.isEmpty || telefono.isEmpty) {
      setState(() => _error = 'Nombre y teléfono son obligatorios.');
      return;
    }
    if (!_esEdicion && password.length < 6) {
      setState(() => _error = 'La contraseña debe tener al menos 6 caracteres.');
      return;
    }
    if (correo.isNotEmpty && !correo.contains('@')) {
      setState(() => _error = 'El correo no es válido.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final functions = Supabase.instance.client.functions;
      if (_esEdicion) {
        await functions.invoke('update-motorizado', body: {
          'usuarioId': widget.motorizado!['id'],
          'nombre': nombre,
          'telefono': telefono,
          'activo': _activo,
          'vehiculoId': _vehiculoId,
          if (password.isNotEmpty) 'nuevaPassword': password,
        });
      } else {
        await functions.invoke('create-motorizado', body: {
          'nombre': nombre,
          'telefono': telefono,
          if (correo.isNotEmpty) 'correo': correo,
          'password': password,
          if (_vehiculoId != null) 'vehiculoId': _vehiculoId,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_esEdicion ? 'Motorizado actualizado' : 'Motorizado creado')),
      );
      Navigator.of(context).pop(true);
    } on FunctionException catch (e) {
      setState(() {
        _cargando = false;
        _error = _mensajeError(e);
      });
    } catch (_) {
      setState(() {
        _cargando = false;
        _error = 'Sin conexión. Revisa tu Internet e inténtalo de nuevo.';
      });
    }
  }

  String _mensajeError(FunctionException e) {
    try {
      final details = e.details?.toString() ?? '';
      if (details.contains('ya está registrado')) {
        return 'Ese correo o teléfono ya está registrado.';
      }
      if (details.contains('administrador')) {
        return 'Solo un administrador puede hacer esto.';
      }
      // El body de la función viene en details como JSON
      final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(details);
      if (match != null) return match.group(1)!;
    } catch (_) {}
    return 'No pudimos guardar. Inténtalo de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_esEdicion ? 'Editar motorizado' : 'Nuevo motorizado')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  hintText: 'Ej: 999888777 — con este número podrá iniciar sesión',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _correoCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Correo (opcional)',
                  hintText: _esEdicion ? 'No se puede cambiar' : 'Si lo dejas vacío se genera uno con el teléfono',
                  prefixIcon: const Icon(Icons.mail_outline),
                  enabled: !_esEdicion,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _esEdicion
                      ? 'Nueva contraseña (opcional)'
                      : 'Contraseña temporal (mín. 6)',
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                initialValue: _vehiculoId,
                decoration: const InputDecoration(
                  labelText: 'Vehículo asignado',
                  prefixIcon: Icon(Icons.delivery_dining_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sin vehículo'),
                  ),
                  ...widget.vehiculos.map((v) => DropdownMenuItem<String?>(
                        value: v['id'] as String?,
                        child: Text(v['nombre'] as String? ?? ''),
                      )),
                ],
                onChanged: (v) => setState(() => _vehiculoId = v),
              ),
              if (_esEdicion) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usuario activo'),
                  subtitle: const Text('Si lo desactivas no podrá iniciar sesión'),
                  value: _activo,
                  onChanged: (v) => setState(() => _activo = v),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.danger)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _cargando ? null : _guardar,
                child: _cargando
                    ? const SizedBox(
                        height: 22, width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_esEdicion ? 'Guardar cambios' : 'Crear motorizado'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
