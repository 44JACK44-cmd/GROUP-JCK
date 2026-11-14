/// Pruebas de la pantalla de Configuración pre-login.
///
/// Verifica que la configuración se puede abrir sin sesión, que expone
/// las secciones pedidas y que no filtra información sensible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gas_app/features/ajustes/ajustes_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> abrir(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AjustesPage()),
    );
    // Deja terminar la carga inicial (versión, permisos, conexión).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
  }

  /// Desplaza hasta que [finder] esté visible en el ListView.
  Future<void> ver(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('muestra las secciones de configuración', (tester) async {
    await abrir(tester);

    expect(find.text('Configuración'), findsOneWidget);
    expect(find.text('Conexión con el servidor'), findsOneWidget);
    expect(find.text('Mapas y navegación'), findsOneWidget);

    await ver(tester, find.text('Permisos de ubicación'));
    expect(find.text('Permisos de ubicación'), findsOneWidget);
    expect(find.text('Audio y navegación'), findsOneWidget);

    await ver(tester, find.text('Versión'));
    expect(find.text('Versión'), findsOneWidget);
    expect(find.text('Diagnóstico'), findsOneWidget);
  });

  testWidgets('no expone claves ni credenciales', (tester) async {
    await abrir(tester);

    final cuerpo = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '');
    final texto = cuerpo.join('\n');

    // La clave pública nunca debe aparecer en pantalla.
    expect(texto.contains('eyJ'), isFalse,
        reason: 'la pantalla no debe mostrar ningún token');
    expect(texto.toLowerCase().contains('password'), isFalse);
    expect(texto.toLowerCase().contains('contraseña:'), isFalse);
  });

  testWidgets('muestra el estado del servidor y el botón de prueba',
      (tester) async {
    await abrir(tester);

    expect(find.text('Servidor'), findsOneWidget);
    expect(find.text('Probar'), findsOneWidget);
    // El host del servidor sí es información no sensible.
    expect(find.textContaining('supabase.co'), findsOneWidget);
  });

  testWidgets('el interruptor del asistente de voz se puede cambiar',
      (tester) async {
    await abrir(tester);

    final voz = find.text('Asistente de voz');
    await ver(tester, voz);
    final sw = find.byType(Switch).last;
    expect(sw, findsOneWidget);

    final antes = tester.widget<Switch>(sw).value;
    await tester.tap(sw);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<Switch>(sw).value, isNot(antes));

    // La preferencia queda guardada en el dispositivo.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ajustes_asistente_voz'), isNot(antes));
  });

  testWidgets('el diagnóstico completo se puede ejecutar', (tester) async {
    await abrir(tester);

    final boton = find.text('Ejecutar diagnóstico completo');
    await ver(tester, boton);
    await tester.tap(boton);
    await tester.pump();
    // `runAsync` deja correr el tiempo real: el diagnóstico hace llamadas
    // de red y usa timeouts que no avanzan con el reloj de pruebas.
    await tester.runAsync(() =>
        Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pump(const Duration(milliseconds: 300));

    final resultado = find.textContaining('Red del dispositivo');
    if (resultado.evaluate().isEmpty) {
      await ver(tester, find.text('Diagnóstico'));
    }
    expect(find.textContaining('Red del dispositivo'), findsOneWidget);
    expect(find.textContaining('Servidor Supabase'), findsOneWidget);
  });
}
