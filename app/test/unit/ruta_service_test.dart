/// Pruebas de las rutas reales y del asistente de voz.
///
/// Lo importante: la ruta que se dibuja sale de Google (polilínea real) y las
/// indicaciones que se dicen son exactamente las de Google. Sin clave, la app
/// avisa claramente y no inventa ninguna ruta.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/config.dart';
import 'package:gas_app/core/maps/ruta_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('decodificación de la ruta real', () {
    test('convierte la polilínea de Google en puntos del recorrido', () {
      // Ejemplo oficial de Google.
      final puntos = RutaService.decodificarPolilinea(
        r'_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      );
      expect(puntos, hasLength(3));
      expect(puntos[0].latitude, closeTo(38.5, 0.00001));
      expect(puntos[0].longitude, closeTo(-120.2, 0.00001));
      expect(puntos[1].latitude, closeTo(40.7, 0.00001));
      expect(puntos[1].longitude, closeTo(-120.95, 0.00001));
      expect(puntos[2].latitude, closeTo(43.252, 0.00001));
      expect(puntos[2].longitude, closeTo(-126.453, 0.00001));
    });

    test('una polilínea vacía no produce puntos', () {
      expect(RutaService.decodificarPolilinea(''), isEmpty);
    });
  });

  group('indicaciones que se dicen en voz alta', () {
    test('una indicación corta se dice en metros', () {
      const paso = InstruccionRuta(
        texto: 'Gira a la derecha en Av. Independencia',
        inicio: LatLng(-16.4, -71.5),
        metros: 300,
      );
      expect(paso.distanciaTexto, '300 m');
      expect(
        paso.paraVoz,
        'Gira a la derecha en Av. Independencia. En 300 metros.',
      );
    });

    test('una indicación larga se dice en kilómetros', () {
      const paso = InstruccionRuta(
        texto: 'Continúa por la carretera',
        inicio: LatLng(-16.4, -71.5),
        metros: 1500,
      );
      expect(paso.distanciaTexto, '1.5 km');
      expect(paso.paraVoz, 'Continúa por la carretera. En 1.5 kilómetros.');
    });

    test('nunca se agrega texto inventado si el paso no trae distancia', () {
      const paso = InstruccionRuta(
        texto: 'Llegaste a tu destino',
        inicio: LatLng(-16.4, -71.5),
      );
      expect(paso.paraVoz, 'Llegaste a tu destino');
    });
  });

  group('resultado de la ruta', () {
    test('sin recorrido no se considera una ruta válida', () {
      const ruta = RutaResultado(error: 'sin clave');
      expect(ruta.hayRuta, isFalse);
      expect(ruta.instrucciones, isEmpty);
    });

    test('con dos puntos sí hay recorrido', () {
      final ruta = RutaResultado(
        puntos: const [LatLng(-16.4, -71.5), LatLng(-16.41, -71.51)],
        destino: const LatLng(-16.41, -71.51),
      );
      expect(ruta.hayRuta, isTrue);
    });

    test('elige la indicación más cercana a donde está el motorizado', () {
      final ruta = RutaResultado(
        puntos: const [
          LatLng(-16.40, -71.50),
          LatLng(-16.45, -71.55),
        ],
        instrucciones: const [
          InstruccionRuta(texto: 'Primera', inicio: LatLng(-16.400, -71.500)),
          InstruccionRuta(texto: 'Segunda', inicio: LatLng(-16.450, -71.550)),
        ],
        destino: const LatLng(-16.45, -71.55),
      );
      expect(ruta.indiceCercano(const LatLng(-16.401, -71.501)), 0);
      expect(ruta.indiceCercano(const LatLng(-16.449, -71.549)), 1);
      expect(ruta.indiceCercano(null), 0);
    });

    test('sin indicaciones devuelve -1 en vez de inventar una', () {
      const ruta = RutaResultado(puntos: [LatLng(0, 0), LatLng(1, 1)]);
      expect(ruta.indiceCercano(const LatLng(0, 0)), -1);
    });
  });

  group('sin clave de Google Maps', () {
    test('no se llama a Google y se explica el motivo', () async {
      // En pruebas no se compila con --dart-define=GOOGLE_MAPS_API_KEY.
      expect(hayClaveGoogleMaps, isFalse);
      final ruta = await const RutaService().calcular(
        origen: const LatLng(-16.40, -71.50),
        destino: const LatLng(-16.45, -71.55),
      );
      expect(ruta.hayRuta, isFalse);
      expect(ruta.error, isNotNull);
      expect(ruta.error!, contains('clave'));
      expect(ruta.puntos, isEmpty);
      expect(ruta.instrucciones, isEmpty);
    });
  });
}
