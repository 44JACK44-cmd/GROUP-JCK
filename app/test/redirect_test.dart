import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gas_reparto/core/router/app_router.dart';
import 'package:gas_reparto/core/router/routes.dart';
import 'package:gas_reparto/features/auth/domain/user_session.dart';

const admin = UserSession(id: 1, nombre: 'Rosa Díaz', usuario: 'admin', rol: UserRole.administrador);
const repartidor = UserSession(id: 2, nombre: 'Carlos', usuario: 'carlos', rol: UserRole.repartidor);

void main() {
  test('mientras carga la sesión se muestra la pantalla inicial', () {
    expect(redirectFor(const AsyncLoading(), Routes.inicio), Routes.splash);
  });

  test('sin sesión siempre va a login', () {
    expect(redirectFor(const AsyncData(null), Routes.inicio), Routes.login);
    expect(redirectFor(const AsyncData(null), Routes.login), isNull);
  });

  test('cada rol entra a su inicio', () {
    expect(redirectFor(const AsyncData(admin), Routes.login), Routes.inicio);
    expect(redirectFor(const AsyncData(repartidor), Routes.login), Routes.entregas);
  });

  test('el repartidor no puede abrir rutas de administrador', () {
    expect(redirectFor(const AsyncData(repartidor), Routes.caja), Routes.entregas);
    expect(redirectFor(const AsyncData(repartidor), Routes.reportes), Routes.entregas);
    expect(redirectFor(const AsyncData(repartidor), Routes.repartoCobros), isNull);
  });

  test('el administrador no entra a la vista del repartidor', () {
    expect(redirectFor(const AsyncData(admin), Routes.entregas), Routes.inicio);
    expect(redirectFor(const AsyncData(admin), Routes.caja), isNull);
  });
}
