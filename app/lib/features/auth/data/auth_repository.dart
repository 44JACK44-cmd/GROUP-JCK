import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../../../core/storage/session_storage.dart';
import '../domain/user_session.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(dioProvider), ref.watch(sessionStorageProvider)),
);

class AuthRepository {
  AuthRepository(this._dio, this._storage);

  final Dio _dio;
  final SessionStorage _storage;

  Future<UserSession?> restore() => _storage.user();

  Future<UserSession> login(String usuario, String password) async {
    try {
      final res = await _dio.post('/api/auth/login', data: {
        'usuario': usuario.trim(),
        'password': password,
        'dispositivo': 'Android',
      });
      final data = res.data as Map<String, dynamic>;
      final user = UserSession.fromJson(data['usuario'] as Map<String, dynamic>);
      await _storage.save(
        AuthTokens(accessToken: data['accessToken'] as String, refreshToken: data['refreshToken'] as String),
        user,
      );
      return user;
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> logout() async {
    final refresh = await _storage.refreshToken();
    await _storage.clear();
    if (refresh == null) return;
    try {
      await _dio.post('/api/auth/logout', data: {'refreshToken': refresh});
    } catch (_) {
      // La sesión local ya se cerró; si no hay conexión, el token vencerá solo.
    }
  }
}
