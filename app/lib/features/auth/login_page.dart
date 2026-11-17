import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  final _telefonoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _verClave = false;
  bool _cargando = false;
  String? _error;

  late final AnimationController _entrada = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )
        ..forward();
  late final Animation<double> _logoAnim = CurvedAnimation(
    parent: _entrada,
    curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
  );
  late final Animation<double> _tituloAnim = CurvedAnimation(
    parent: _entrada,
    curve: const Interval(0.15, 0.6, curve: Curves.easeOut),
  );
  late final Animation<double> _formAnim = CurvedAnimation(
    parent: _entrada,
    curve: const Interval(0.3, 0.85, curve: Curves.easeOut),
  );
  late final Animation<double> _botonAnim = CurvedAnimation(
    parent: _entrada,
    curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _entrada.dispose();
    _telefonoCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (_cargando) return;
    final telefono = _telefonoCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (telefono.isEmpty || password.isEmpty) {
      setState(() => _error = 'Ingresa tu usuario y contraseña.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    final error = await ref.read(authProvider.notifier).login(telefono, password);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _error = error;
    });
  }

  Widget _aparecer(Animation<double> anim, Widget child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/ajustes'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _aparecer(
                  _logoAnim,
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1).animate(_logoAnim),
                    child: Icon(Icons.local_fire_department,
                        size: 72, color: AppTheme.primary),
                  ),
                ),
                const SizedBox(height: 12),
                _aparecer(
                  _tituloAnim,
                  Column(
                    children: [
                      Text(
                        'GasApp',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pedidos y reparto de gas',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                _aparecer(
                  _formAnim,
                  Column(
                    children: [
                      TextField(
                        controller: _telefonoCtrl,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_cargando,
                        decoration: const InputDecoration(
                          labelText: 'Correo o teléfono',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: !_verClave,
                        enabled: !_cargando,
                        onSubmitted: (_) => _entrar(),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _verClave ? 'Ocultar' : 'Mostrar',
                            icon: Icon(_verClave
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () =>
                                setState(() => _verClave = !_verClave),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.danger),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                _aparecer(
                  _botonAnim,
                  FilledButton(
                    onPressed: _cargando ? null : _entrar,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: _cargando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Iniciar sesión',
                            style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.push('/registro-empresa'),
                  child: const Text('¿No tienes empresa? Regístrala aquí'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
