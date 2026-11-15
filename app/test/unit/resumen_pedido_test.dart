import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/domain/resumen_pedido.dart';

void main() {
  final pedido = {
    'detalle_pedido': [
      {
        'cantidad': 2,
        'productos': {'nombre': 'Balón', 'capacidad_kg': 10, 'tipo': 'PRODUCTO'},
      },
      {
        'cantidad': 1,
        'productos': {'nombre': 'Fierro / Balón vacío', 'capacidad_kg': null, 'tipo': 'RETORNABLE'},
      },
    ],
  };

  test('resumenProductos lista las líneas', () {
    expect(resumenProductos(pedido), 'Balón 10kg × 2 · Fierro / Balón vacío × 1');
  });

  test('balonesDe suma solo los vendibles', () {
    expect(balonesDe(pedido), 2);
  });

  test('fierrosDe suma los retornables', () {
    expect(fierrosDe(pedido), 1);
  });

  test('sin detalle no rompe', () {
    expect(resumenProductos({}), '');
    expect(balonesDe({}), 1);
    expect(fierrosDe({}), 0);
  });
}
