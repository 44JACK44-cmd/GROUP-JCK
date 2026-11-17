import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import 'auth_controller.dart';

/// Registro de una nueva empresa desde la APK.
/// Llama a la Edge Function `register-empresa` (crea empresa + admin).
class RegisterEmpresaPage extends ConsumerStatefulWidget {
  RegisterEmpresaPage({super.key});

  @override
  ConsumerState<RegisterEmpresaPage> createState() => _RegisterEmpresaPageState();
}

class _RegisterEmpresaPageState extends ConsumerState<RegisterEmpresaPage> {
  final _empresaCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_empresaCtrl, _nombreCtrl, _telefonoCtrl, _correoCtrl, _passwordCtrl, _confirmarCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _registrar() async {
    final empresa = _empresaCtrl.text.trim();
    final nombre = _nombreCtrl.text.trim();
    final telefono = _telefonoCtrl.text.trim();
    final correo = _correoCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (empresa.isEmpty || nombre.isEmpty || telefono.isEmpty || correo.isEmpty || password.isEmpty) {
      setState(() => _error = 'Completa todos los campos.');
      return;
    }
    if (password != _confirmarCtrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'La contraseña debe tener al menos 6 caracteres.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'register-empresa',
        body: {
          'nombreEmpresa': empresa,
          'nombreAdmin': nombre,
          'telefono': telefono,
          'correo': correo,
          'password': password,
        },
      );

      if (response.status != 200) {
        throw Exception(_extraerError(response.data));
      }

      // Login automático con el correo y contraseña recién creados
      final loginError = await ref.read(authProvider.notifier).login(correo, password);
      if (!mounted) return;
      if (loginError != null) {
        setState(() {
          _cargando = false;
          _error = 'Empresa creada, pero no pudimos iniciar sesión: $loginError';
        });
      }
      // Si el login fue exitoso, el router redirige solo al inicio.
    } on FunctionException catch (e) {
      setState(() {
        _cargando = false;
        _error = _mensajeFuncion(e);
      });
    } catch (_) {
      setState(() {
        _cargando = false;
        _error = 'Sin conexión. Revisa tu Internet e inténtalo de nuevo.';
      });
    }
  }

  String _extraerError(dynamic data) {
    if (data is Map && data['error'] != null) return data['error'].toString();
    return 'No pudimos completar el registro.';
  }

  String _mensajeFuncion(FunctionException e) {
    try {
      final body = e.details is String ? e.details : e.toString();
      if (body.contains('empresa ya está registrada')) {
        return 'Esta empresa ya está registrada.';
      }
      if (body.contains('correo ya está asociado')) {
        return 'El correo ya está asociado a una cuenta.';
      }
      if (body.contains('teléfono')) {
        return 'Ese teléfono ya está registrado en otra empresa.';
      }
    } catch (_) {}
    return 'No pudimos completar el registro. Inténtalo de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Registrar mi empresa')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _empresaCtrl,
                decoration: InputDecoration(
                  labelText: 'Nombre de la empresa',
                  hintText: 'Ej: Grupo Gas SAC',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              SizedBox(height: 14),
              TextField(
                controller: _nombreCtrl,
                decoration: InputDecoration(
                  labelText: 'Tu nombre (administrador)',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              SizedBox(height: 14),
              TextField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Teléfono',
                  hintText: 'Ej: 999888777',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              SizedBox(height: 14),
              TextField(
                controller: _correoCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  hintText: 'tucorreo@ejemplo.com',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              SizedBox(height: 14),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Contraseña (mín. 6 caracteres)',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              SizedBox(height: 14),
              TextField(
                controller: _confirmarCtrl,
                obscureText: true,
                onSubmitted: (_) => _registrar(),
                decoration: InputDecoration(
                  labelText: 'Confirmar contraseña',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              if (_error != null) ...[
                SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: AppTheme.danger)),
              ],
              SizedBox(height: 24),
              FilledButton(
                onPressed: _cargando ? null : _registrar,
                child: _cargando
                    ? SizedBox(
                        height: 22, width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text('Crear mi empresa'),
              ),
              SizedBox(height: 12),
              Text(
                'Al registrarte crearás tu empresa y tu usuario administrador. Después podrás agregar motorizados, clientes y pedidos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textoMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}