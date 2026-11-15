import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/domain/precio.dart';

void main() {
  group('PrecioLibre', () {
    test('acepta enteros y decimales', () {
      expect(PrecioLibre.parse('55'), 55.0);
      expect(PrecioLibre.parse('55.5'), 55.5);
      expect(PrecioLibre.parse('55,50'), 55.5);
      expect(PrecioLibre.parse('S/ 63.50'), 63.5);
    });

    test('rechaza vacío, texto y valores no positivos', () {
      expect(PrecioLibre.parse(''), isNull);
      expect(PrecioLibre.parse('abc'), isNull);
      expect(PrecioLibre.parse('0'), isNull);
      expect(PrecioLibre.parse('-5'), isNull);
    });

    test('esValido sigue a parse', () {
      expect(PrecioLibre.esValido('55'), isTrue);
      expect(PrecioLibre.esValido(''), isFalse);
    });

    test('sugerido prioriza el precio del cliente', () {
      expect(PrecioLibre.sugerido(precioCliente: 50, precioBase: 45), 50.0);
      expect(PrecioLibre.sugerido(precioCliente: null, precioBase: 45), 45.0);
      expect(PrecioLibre.sugerido(precioCliente: null, precioBase: 0), isNull);
    });

    test('paraEditar quita ceros de relleno', () {
      expect(PrecioLibre.paraEditar(55), '55');
      expect(PrecioLibre.paraEditar(55.5), '55.50');
    });
  });
}
