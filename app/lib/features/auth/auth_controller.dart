import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';

enum AuthStatus { cargando, autenticado, noAutenticado }

class AuthState {
  final AuthStatus status;
  final String? nombre;
  final String? telefono;
  final String? rol;
  final String? usuarioId;
  final String? empresaId;
  final String? empresaNombre;

  const AuthState({
    required this.status,
    this.nombre,
    this.rol,
    this.usuarioId,
    this.telefono,
    this.empresaId,
    this.empresaNombre,
  });

  bool get esAdmin => rol == 'ADMIN';
  bool get esMotorizado => rol == 'MOTORIZADO';
}

class AuthNotifier extends Notifier<AuthState> {
  SupabaseClient get _sb => Supabase.instance.client;

  @override
  AuthState build() {
    final session = _sb.auth.currentSession;
    if (session == null) {
      return const AuthState(status: AuthStatus.noAutenticado);
    }
    _cargarPerfil(session.user.id);
    return const AuthState(status: AuthStatus.cargando);
  }

  Future<void> _cargarPerfil(String userId) async {
    try {
      final perfil = await _sb
          .from('perfiles')
          .select('nombre, rol, telefono, empresa_id')
          .eq('id', userId)
          .single();

      final empresaId = perfil['empresa_id'] as String?;
      String? empresaNombre;
      if (empresaId != null) {
        final empresa = await _sb
            .from('empresas')
            .select('nombre')
            .eq('id', empresaId)
            .maybeSingle();
        empresaNombre = empresa?['nombre'] as String?;
      }

      state = AuthState(
        status: AuthStatus.autenticado,
        nombre: perfil['nombre'] as String?,
        telefono: perfil['telefono'] as String?,
        rol: perfil['rol'] as String?,
        usuarioId: userId,
        empresaId: empresaId,
        empresaNombre: empresaNombre,
      );
    } catch (_) {
      // Sesión sin perfil: cerrar sesión para no dejar estado inconsistente.
      await _sb.auth.signOut();
      state = const AuthState(status: AuthStatus.noAutenticado);
    }
  }

  /// Devuelve null si el login fue exitoso, o el mensaje de error.
  Future<String?> login(String usuario, String password) async {
    try {
      // Si no escribe un correo, se asume teléfono → usuario@grupojck.app
      final input = usuario.trim();
      final email = input.contains('@') ? input : '$input@$emailDomain';

      final response = await _sb.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final userId = response.user?.id;
      if (userId == null) {
        return 'No pudimos iniciar sesión. Inténtalo de nuevo.';
      }

      await _cargarPerfil(userId);
      return state.status == AuthStatus.autenticado
          ? null
          : 'Tu usuario no está registrado en el sistema.';
    } on AuthException catch (e) {
      return _mensajeError(e);
    } catch (_) {
      return 'Sin conexión. Revisa tu Internet e inténtalo de nuevo.';
    }
  }

  String _mensajeError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login') || msg.contains('credentials')) {
      return 'Usuario o contraseña incorrectos.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Tu cuenta no está confirmada. Contacta al administrador.';
    }
    return 'No pudimos iniciar sesión. Inténtalo de nuevo.';
  }

  Future<void> logout() async {
    await _sb.auth.signOut();
    state = const AuthState(status: AuthStatus.noAutenticado);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
