/// Pruebas del formato de dinero, fechas y antigüedad.
import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/domain/formato.dart';

void main() {
  group('dinero', () {
    test('muestra el monto con dos decimales', () {
      expect(dinero(45), 'S/ 45.00');
      expect(dinero(45.5), 'S/ 45.50');
    });

    test('sin decimales quita los ceros', () {
      expect(dinero(45, conDecimales: false), 'S/ 45');
      expect(dinero(45.5, conDecimales: false), 'S/ 45.50');
    });

    test('un valor nulo es cero', () {
      expect(dinero(null), 'S/ 0.00');
    });
  });

  group('antiguedad', () {
    final ahora = DateTime(2026, 11, 13, 12, 0);

    test('un pedido recién creado dice "Hace un momento"', () {
      expect(
        antiguedad(ahora.subtract(const Duration(seconds: 20)), ahora: ahora),
        'Hace un momento',
      );
    });

    test('un pedido de 35 minutos', () {
      expect(
        antiguedad(ahora.subtract(const Duration(minutes: 35)), ahora: ahora),
        'Hace 35 min',
      );
    });

    test('un pedido de 2 h 30 min', () {
      expect(
        antiguedad(ahora.subtract(const Duration(hours: 2, minutes: 30)), ahora: ahora),
        'Hace 2 h 30 min',
      );
    });

    test('un pedido de 1 h exacta', () {
      expect(
        antiguedad(ahora.subtract(const Duration(hours: 1)), ahora: ahora),
        'Hace 1 h',
      );
    });

    test('un pedido de varios días', () {
      expect(
        antiguedad(ahora.subtract(const Duration(days: 3)), ahora: ahora),
        'Hace 3 días',
      );
    });
  });

  group('fechas', () {
    final f = DateTime(2026, 11, 13, 14, 30);

    test('fecha corta con año', () {
      expect(fechaCorta(f), '13/11/2026');
    });

    test('fecha con hora', () {
      expect(fechaHora(f), '13/11/2026 14:30');
    });

    test('fecha relativa: hoy, ayer y fecha', () {
      final hoy = DateTime(2026, 11, 13, 9, 5);
      expect(fechaRelativa(hoy, ahora: DateTime(2026, 11, 13, 18, 0)), 'Hoy 09:05');
      expect(
        fechaRelativa(DateTime(2026, 11, 12, 9, 5), ahora: DateTime(2026, 11, 13, 18, 0)),
        'Ayer 09:05',
      );
      expect(
        fechaRelativa(DateTime(2026, 11, 1, 9, 5), ahora: DateTime(2026, 11, 13, 18, 0)),
        '01/11 09:05',
      );
    });

    test('parsea el ISO de Supabase', () {
      final p = parseFecha('2026-11-13T20:08:45.294071+00:00');
      expect(p, isNotNull);
      expect(p!.toUtc().year, 2026);
      expect(parseFecha(null), isNull);
    });
  });

  group('inicios de periodo', () {
    test('inicio del día a las 00:00', () {
      final d = inicioHoy(DateTime(2026, 11, 13, 15, 30));
      expect(d, DateTime(2026, 11, 13));
    });

    test('inicio de semana: lunes', () {
      // 13/11/2026 es viernes → la semana empieza el lunes 9.
      final d = inicioSemana(DateTime(2026, 11, 13, 15, 30));
      expect(d, DateTime(2026, 11, 9));
      expect(d.weekday, DateTime.monday);
    });

    test('inicio de mes', () {
      expect(inicioMes(DateTime(2026, 11, 13)), DateTime(2026, 11, 1));
    });
  });

  group('metodoPago', () {
    test('muestra nombres entendibles', () {
      expect(metodoPago('YAPE'), 'Yape');
      expect(metodoPago('EFECTIVO'), 'Efectivo');
      expect(metodoPago('DEUDA'), 'Quedó debiendo');
      expect(metodoPago(null), 'Pendiente');
    });
  });
}
