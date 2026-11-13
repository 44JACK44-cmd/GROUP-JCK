import 'package:dio/dio.dart';

/// Error listo para mostrar al usuario. Nunca contiene detalles técnicos.
class AppFailure implements Exception {
  const AppFailure(this.message, {this.code});

  final String message;
  final String? code;

  static const sinConexion =
      'No pudimos conectar con el servidor.\nRevisa tu conexión e inténtalo nuevamente.';
  static const generico = 'Algo salió mal. Inténtalo nuevamente.';

  factory AppFailure.from(Object error) {
    if (error is AppFailure) return error;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return const AppFailure(sinConexion, code: 'SIN_CONEXION');
        default:
          break;
      }
      final data = error.response?.data;
      final status = error.response?.statusCode ?? 0;
      if (data is Map && data['mensaje'] is String && status < 500) {
        return AppFailure(data['mensaje'] as String, code: data['codigo'] as String?);
      }
    }
    return const AppFailure(generico);
  }

  @override
  String toString() => message;
}
