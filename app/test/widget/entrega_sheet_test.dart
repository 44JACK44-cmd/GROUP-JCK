/// Pruebas del formulario de entrega: cuánto se cobró, con qué método,
/// si quedó deuda y qué pasa con el balón vacío.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/data/entregas_repo.dart';
import 'package:gas_app/features/pedidos/entrega_sheet.dart';

Future<DatosEntrega?> _abrirYConfirmar(
  WidgetTester tester, {
  required double total,
  int balones = 2,
  Future<void> Function(WidgetTester)? interaccion,
}) async {
  DatosEntrega? resultado;

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            resultado = await mostrarFormularioEntrega(
              context,
              total: total,
              cantidadBalones: balones,
            );
          },
          child: const Text('abrir'),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();

  if (interaccion != null) {
    await interaccion(tester);
  } else {
    await _tocar(tester, 'Finalizar entrega');
  }

  return resultado;
}

/// Toca un botón de la hoja por su texto exacto.
Future<void> _tocar(WidgetTester tester, String texto, {int indice = 0}) async {
  final finder = find.text(texto);
  await tester.ensureVisible(finder.at(indice));
  await tester.pumpAndSettle();
  await tester.tap(finder.at(indice), warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('el monto por defecto es el total a cobrar', (tester) async {
    final datos = await _abrirYConfirmar(tester, total: 45);
    expect(datos, isNotNull);
    expect(datos!.montoCobrado, 45);
    expect(datos.metodo, 'EFECTIVO');
  });

  testWidgets('quedó debiendo → no hay pago y queda la deuda', (tester) async {
    final datos = await _abrirYConfirmar(
      tester,
      total: 45,
      interaccion: (t) async {
        await _tocar(t, '🟠 Quedó debiendo');
        await _tocar(t, 'Finalizar entrega');
      },
    );
    expect(datos, isNotNull);
    expect(datos!.montoCobrado, 0);
    expect(datos.metodo, 'DEUDA');
    expect(datos.quedanDeuda(45), isTrue);
    expect(datos.deuda(45), 45);
  });

  testWidgets('pago parcial: se registra lo cobrado y queda deuda', (tester) async {
    final datos = await _abrirYConfirmar(
      tester,
      total: 45,
      interaccion: (t) async {
        await t.enterText(find.byType(TextField).first, '20');
        await t.pumpAndSettle();
        await _tocar(t, 'Finalizar entrega');
      },
    );
    expect(datos, isNotNull);
    expect(datos!.montoCobrado, 20);
    expect(datos.quedanDeuda(45), isTrue);
    expect(datos.deuda(45), 25);
  });

  testWidgets('pagar con Yape queda registrado como método Yape', (tester) async {
    final datos = await _abrirYConfirmar(
      tester,
      total: 45,
      interaccion: (t) async {
        await _tocar(t, '📱 Yape');
        await _tocar(t, 'Finalizar entrega');
      },
    );
    expect(datos, isNotNull);
    expect(datos!.metodo, 'YAPE');
    expect(datos.montoCobrado, 45);
    expect(datos.quedanDeuda(45), isFalse);
  });

  testWidgets('por defecto el balón vacío queda pendiente', (tester) async {
    final datos = await _abrirYConfirmar(tester, total: 45);
    expect(datos!.balonVacio, EstadoBalonVacio.noRecibido);
  });

  testWidgets('si el cliente devuelve el vacío se registra recibido', (tester) async {
    final datos = await _abrirYConfirmar(
      tester,
      total: 45,
      interaccion: (t) async {
        // El botón "Sí" del bloque del balón vacío es el primero de los dos.
        await _tocar(t, 'Sí', indice: 0);
        await _tocar(t, 'Finalizar entrega');
      },
    );
    expect(datos!.balonVacio, EstadoBalonVacio.recibido);
  });

  testWidgets('se guarda la cantidad de balones entregados', (tester) async {
    final datos = await _abrirYConfirmar(tester, total: 90, balones: 2);
    expect(datos!.cantidadBalones, 2);
  });

  testWidgets('no se puede cobrar más que el total', (tester) async {
    final datos = await _abrirYConfirmar(
      tester,
      total: 45,
      interaccion: (t) async {
        await t.enterText(find.byType(TextField).first, '100');
        await t.pumpAndSettle();
        await _tocar(t, 'Finalizar entrega');
      },
    );
    // La hoja sigue abierta (no se cerró), así que no hay resultado.
    expect(datos, isNull);
    expect(find.text('Finalizar entrega'), findsOneWidget);
  });

  test('el estado de pago se calcula según lo cobrado', () {
    expect(EstadoPagoEntrega.calcular(45, 45), EstadoPagoEntrega.pagado);
    expect(EstadoPagoEntrega.calcular(45, 45.01), EstadoPagoEntrega.pagado);
    expect(EstadoPagoEntrega.calcular(45, 44.99), EstadoPagoEntrega.parcial);
    expect(EstadoPagoEntrega.calcular(45, 20), EstadoPagoEntrega.parcial);
    expect(EstadoPagoEntrega.calcular(45, 0), EstadoPagoEntrega.pendiente);
  });
}
