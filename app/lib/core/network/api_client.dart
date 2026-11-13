import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/session_storage.dart';
import '../../features/auth/domain/user_session.dart';

const _authPaths = ['/api/auth/login', '/api/auth/refresh', '/api/auth/logout'];

BaseOptions _options() => BaseOptions(
      baseUrl: AppConfig.apiUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      contentType: Headers.jsonContentType,
    );

/// Crea el cliente HTTP. Añade el token y lo renueva automáticamente cuando vence.
Dio createApiClient({required SessionStorage storage, required void Function() onSessionExpired}) {
  final dio = Dio(_options());
  dio.interceptors.add(AuthInterceptor(dio, storage, onSessionExpired));
  return dio;
}

class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._dio, this._storage, this._onSessionExpired, {Dio? refreshDio})
      : _refreshDio = refreshDio ?? Dio(_options());

  final Dio _dio;
  final Dio _refreshDio;
  final SessionStorage _storage;
  final void Function() _onSessionExpired;

  static const _retried = 'auth_retried';

  bool _isAuthPath(RequestOptions o) => _authPaths.contains(o.path);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isAuthPath(options)) {
      final token = await _storage.accessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    if (err.response?.statusCode != 401 || _isAuthPath(req) || req.extra[_retried] == true) {
      return handler.next(err);
    }
    final refreshed = await _refresh();
    if (!refreshed) {
      await _storage.clear();
      _onSessionExpired();
      return handler.next(err);
    }
    try {
      req.extra[_retried] = true;
      req.headers['Authorization'] = 'Bearer ${await _storage.accessToken()}';
      handler.resolve(await _dio.fetch(req));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<bool> _refresh() async {
    final refresh = await _storage.refreshToken();
    if (refresh == null) return false;
    try {
      final res = await _refreshDio.post('/api/auth/refresh', data: {'refreshToken': refresh});
      final data = res.data as Map<String, dynamic>;
      await _storage.save(
        AuthTokens(accessToken: data['accessToken'] as String, refreshToken: data['refreshToken'] as String),
        UserSession.fromJson(data['usuario'] as Map<String, dynamic>),
      );
      return true;
    } on DioException catch (e) {
      // Sin conexión no se cierra la sesión: el usuario podrá seguir cuando vuelva Internet.
      final status = e.response?.statusCode;
      if (status == null) rethrow;
      return false;
    }
  }
}
