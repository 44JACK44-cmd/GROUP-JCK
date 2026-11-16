/// Reglas puras de la rendición del flujo simple:
/// fondo + efectivo − gastos en efectivo = esperado, y declarado − esperado =
/// diferencia. Yape y deuda nunca se mezclan con el efectivo.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/data/rendicion_repo.dart';

void main() {
  group('efectivo esperado', () {
    test('fondo + efectivo − gastos en efectivo', () {
      final esperado = RendicionRepo.calcularEsperado(
        fondoInicial: 100,
        efectivoCobrado: 192,
        gastosEfectivo: 35,
      );
      expect(esperado, 257);
    });

    test('el Yape y la deuda no cambian el efectivo esperado', () {
      final esperado = RendicionRepo.calcularEsperado(
        fondoInicial: 100,
        efectivoCobrado: 192,
        gastosEfectivo: 35,
      );
      // 144 de Yape y 48 de deuda no aparecen en esta cuenta.
      expect(esperado, 257);
    });

    test('si los gastos superan al efectivo, el esperado no es negativo', () {
      final esperado = RendicionRepo.calcularEsperado(
        fondoInicial: 0,
        efectivoCobrado: 20,
        gastosEfectivo: 35,
      );
      expect(esperado, 0);
    });
  });

  group('diferencia', () {
    test('cuadra exacto', () {
      expect(
        RendicionRepo.calcularDiferencia(declarado: 257, esperado: 257),
        0,
      );
    });

    test('declara de menos: falta dinero', () {
      expect(
        RendicionRepo.calcularDiferencia(declarado: 250, esperado: 257),
        -7,
      );
    });

    test('declara de más: sobra dinero', () {
      expect(
        RendicionRepo.calcularDiferencia(declarado: 260, esperado: 257),
        3,
      );
    });
  });

  group('Rendicion vacío', () {
    test('una jornada con solo fondo no está vacía', () {
      const r = Rendicion(fondoInicial: 100);
      expect(r.vacio, isFalse);
    });

    test('una jornada con solo gasto no está vacía', () {
      const r = Rendicion(gastosTotal: 35);
      expect(r.vacio, isFalse);
    });

    test('sin movimientos sí está vacía', () {
      const r = Rendicion();
      expect(r.vacio, isTrue);
    });

    test('la diferencia solo se marca si hubo declaración', () {
      const sinDeclarar = Rendicion(efectivoEsperado: 257);
      expect(sinDeclarar.tieneDiferencia, isFalse);

      const conDeclarar = Rendicion(
        efectivoEsperado: 257,
        efectivoDeclarado: 250,
        diferencia: -7,
        hayDeclaracion: true,
      );
      expect(conDeclarar.tieneDiferencia, isTrue);
    });
  });
}
