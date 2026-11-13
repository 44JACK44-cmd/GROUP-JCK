import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gas_reparto/app.dart';
import 'package:gas_reparto/core/errors/app_failure.dart';
import 'package:gas_reparto/features/auth/data/auth_repository.dart';
import 'package:gas_reparto/features/auth/domain/user_session.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repo;

  setUp(() {
    repo = MockAuthRepository();
    when(() => repo.restore()).thenAnswer((_) async => null);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: const GasRepartoApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> ingresar(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'u');
    await tester.enterText(find.byType(TextField).at(1), 'p');
    await tester.tap(find.text('INGRESAR'));
    await tester.pumpAndSettle();
  }

  testWidgets('pide usuario y contraseña antes de ingresar', (tester) async {
    await pump(tester);
    await tester.tap(find.text('INGRESAR'));
    await tester.pumpAndSettle();
    expect(find.text('Escribe tu usuario'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });

  testWidgets('muestra el error de forma amigable', (tester) async {
    when(() => repo.login(any(), any()))
        .thenThrow(const AppFailure('Usuario o contraseña incorrectos.'));
    await pump(tester);
    await ingresar(tester);
    expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
  });

  testWidgets('el administrador ve inicio con 5 pestañas', (tester) async {
    when(() => repo.login(any(), any())).thenAnswer((_) async =>
        const UserSession(id: 1, nombre: 'Rosa Díaz', usuario: 'admin', rol: UserRole.administrador));
    await pump(tester);
    await ingresar(tester);
    expect(find.text('NUEVO PEDIDO'), findsOneWidget);
    for (final tab in ['Inicio', 'Pedidos', 'Clientes', 'Cobros', 'Más']) {
      expect(find.text(tab), findsWidgets);
    }
  });

  testWidgets('el repartidor ve solo sus 3 pestañas', (tester) async {
    when(() => repo.login(any(), any())).thenAnswer((_) async =>
        const UserSession(id: 2, nombre: 'Carlos', usuario: 'carlos', rol: UserRole.repartidor));
    await pump(tester);
    await ingresar(tester);
    expect(find.text('No tienes entregas pendientes'), findsOneWidget);
    expect(find.text('Entregas'), findsOneWidget);
    expect(find.text('Clientes'), findsNothing);
    expect(find.text('NUEVO PEDIDO'), findsNothing);
  });
}
