/// La evidencia de Yape debe estar disponible en TODOS los pagos,
/// no solo en la entrega de pedidos.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/features/pagos/pago_sheet.dart';

Future<void> _abrir(WidgetTester tester, Future<void> Function(WidgetTester) accion) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          onPressed: () => mostrarHojaPago(
            context,
            clienteNombre: 'Cliente Prueba',
            suggestedMonto: 50,
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  await accion(tester);
}

void main() {
  testWidgets('al pagar con Yape aparece la opción de foto', (tester) async {
    await _abrir(tester, (t) async {
      await t.tap(find.text('Yape'));
      await t.pumpAndSettle();
      expect(find.text('Tomar foto'), findsOneWidget);
      expect(find.text('Galería'), findsOneWidget);
      expect(
        find.text('Foto del comprobante *'),
        findsOneWidget,
      );
    });
  });

  testWidgets('sin foto se pide confirmación antes de registrar', (tester) async {
    await _abrir(tester, (t) async {
      await t.tap(find.text('Yape'));
      await t.pumpAndSettle();
      await t.tap(find.text('Registrar pago'));
      await t.pumpAndSettle();
      expect(find.text('Sin comprobante'), findsOneWidget);
      expect(find.text('Continuar sin foto'), findsOneWidget);
    });
  });
}
