import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gas_reparto/core/errors/app_failure.dart';

void main() {
  final req = RequestOptions(path: '/api/x');

  test('sin conexión muestra un mensaje cotidiano', () {
    final f = AppFailure.from(DioException(requestOptions: req, type: DioExceptionType.connectionError));
    expect(f.message, AppFailure.sinConexion);
  });

  test('usa el mensaje amigable del servidor en errores de negocio', () {
    final f = AppFailure.from(DioException(
      requestOptions: req,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: req,
        statusCode: 401,
        data: {'codigo': 'CREDENCIALES_INVALIDAS', 'mensaje': 'Usuario o contraseña incorrectos.'},
      ),
    ));
    expect(f.message, 'Usuario o contraseña incorrectos.');
    expect(f.code, 'CREDENCIALES_INVALIDAS');
  });

  test('nunca muestra errores técnicos del servidor', () {
    final f = AppFailure.from(DioException(
      requestOptions: req,
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: req, statusCode: 500, data: 'NullPointerException'),
    ));
    expect(f.message, AppFailure.generico);
  });
}
