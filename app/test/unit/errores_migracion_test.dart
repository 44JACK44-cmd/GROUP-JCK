/// Los errores de base de datos se traducen a avisos accionables: cuando la
/// migración del paso 15 falta, el mensaje dice qué Hay que ejecutar en vez de
/// un "No autorizado" que no explica nada.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/data/sb.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('42501 explica que falta el paso 15', () {
    final e = traducirError(
      PostgrestException(
        message: 'new row violates row-level security policy for table "gastos"',
        code: '42501',
      ),
      contexto: 'No pudimos registrar el gasto',
    );
    expect(e.mensaje, contains('paso 15'));
    expect(e.mensaje, contains('SQL Editor'));
  });

  test('42703 explica que falta una columna', () {
    final e = traducirError(
      PostgrestException(
        message: 'column pagos.comprobante_url does not exist',
        code: '42703',
      ),
    );
    expect(e.mensaje, contains('paso 15'));
  });

  test('PGRST205 explica que falta una tabla', () {
    final e = traducirError(
      PostgrestException(
        message: "Could not find the table 'public.fondo_vuelto' in the schema cache",
        code: 'PGRST205',
      ),
    );
    expect(e.mensaje, contains('paso 15'));
  });

  test('detectores de esquema incompleto', () {
    expect(esTablaAusente(PostgrestException(message: 'x', code: '42P01')), isTrue);
    expect(esTablaAusente(PostgrestException(message: 'x', code: 'PGRST205')), isTrue);
    expect(esColumnaAusente(PostgrestException(message: 'x', code: '42703')), isTrue);
    expect(esPermisoDenegado(PostgrestException(message: 'x', code: '42501')), isTrue);
  });
}
