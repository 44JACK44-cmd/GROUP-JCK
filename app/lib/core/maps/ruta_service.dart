/// Rutas reales con Google Directions.
///
/// Regla: la ruta que se dibuja y las indicaciones que se dicen salen SIEMPRE
/// de la respuesta real de Google. Nunca se inventan mensajes ni se une el
/// origen con el destino con una línea recta: si no hay ruta, se dice.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config.dart';

/// Una indicación concreta del recorrido (paso de Google Directions).
class InstruccionRuta {
  /// Texto ya limpio (sin HTML) que se muestra y se lee en voz alta.
  final String texto;

  /// Maniobra de Google (`turn-left`, `roundabout-right`, ...), si la hay.
  final String? maniobra;

  /// Distancia del tramo en metros.
  final int metros;

  /// Punto donde empieza el tramo (para saber cuál toca ahora).
  final LatLng inicio;

  const InstruccionRuta({
    required this.texto,
    required this.inicio,
    this.maniobra,
    this.metros = 0,
  });

  /// Lo que se dice en voz alta: el texto real de Google + su distancia.
  String get paraVoz {
    if (metros <= 0) return texto;
    final km = metros >= 1000;
    final distancia = km
        ? '${(metros / 1000).toStringAsFixed(1)} kilómetros'
        : '$metros metros';
    return '$texto. En $distancia.';
  }

  String get distanciaTexto =>
      metros >= 1000 ? '${(metros / 1000).toStringAsFixed(1)} km' : '$metros m';
}

/// Resultado de pedir una ruta.
class RutaResultado {
  /// Puntos del recorrido real (vienen codificados por Google).
  final List<LatLng> puntos;

  /// Indicaciones en orden.
  final List<InstruccionRuta> instrucciones;

  final String distanciaTexto;
  final String duracionTexto;
  final LatLng destino;

  /// `null` si todo salió bien; si no, un motivo en español para mostrar.
  final String? error;

  const RutaResultado({
    this.puntos = const [],
    this.instrucciones = const [],
    this.distanciaTexto = '',
    this.duracionTexto = '',
    this.destino = const LatLng(0, 0),
    this.error,
  });

  bool get hayRuta => error == null && puntos.length > 1;

  /// Indicación más cercana a una posición actual del motorizado.
  ///
  /// Sirve para que la voz diga el tramo que corresponde ahora y no siempre
  /// el primero. Si no hay indicaciones, devuelve -1.
  int indiceCercano(LatLng? posicion) {
    if (instrucciones.isEmpty) return -1;
    if (posicion == null) return 0;
    const medidor = Distance();
    var mejor = 0;
    var menor = double.infinity;
    for (var i = 0; i < instrucciones.length; i++) {
      final d = medidor(posicion, instrucciones[i].inicio);
      if (d < menor) {
        menor = d;
        mejor = i;
      }
    }
    return mejor;
  }
}

class RutaService {
  const RutaService();

  static const _base = 'https://maps.googleapis.com/maps/api/directions/json';

  /// Calcula el recorrido en auto desde [origen] hasta [destino].
  ///
  /// Sin clave configurada no se llama a Google: se devuelve un error claro
  /// para que la pantalla muestre el mapa alternativo.
  Future<RutaResultado> calcular({
    required LatLng origen,
    required LatLng destino,
  }) async {
    if (!hayClaveGoogleMaps) {
      return RutaResultado(
        destino: destino,
        error: 'Esta compilación no tiene clave de Google Maps. '
            'Se muestra un mapa alternativo.',
      );
    }

    final uri = Uri.parse(_base).replace(queryParameters: {
      'origin': '${origen.latitude},${origen.longitude}',
      'destination': '${destino.latitude},${destino.longitude}',
      'mode': 'driving',
      'language': 'es',
      'region': 'pe',
      'alternatives': 'false',
      'key': googleMapsApiKey,
    });

    http.Response respuesta;
    try {
      respuesta = await http.get(uri).timeout(Duration(seconds: 15));
    } on TimeoutException {
      return RutaResultado(
        destino: destino,
        error: 'Google no respondió a tiempo. Revisa tu conexión.',
      );
    } on SocketException {
      return RutaResultado(
        destino: destino,
        error: 'Sin internet: no se pudo calcular la ruta.',
      );
    } catch (_) {
      return RutaResultado(
        destino: destino,
        error: 'No se pudo calcular la ruta en este momento.',
      );
    }

    if (respuesta.statusCode != 200) {
      return RutaResultado(
        destino: destino,
        error: 'El servicio de rutas respondió con un error '
            '(${respuesta.statusCode}).',
      );
    }

    Map<String, dynamic> datos;
    try {
      datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
    } catch (_) {
      return RutaResultado(
        destino: destino,
        error: 'La respuesta del servicio de rutas no se pudo leer.',
      );
    }

    final estado = datos['status'] as String? ?? 'UNKNOWN_ERROR';
    final mensajeGoogle = (datos['error_message'] as String?)?.trim();
    if (estado != 'OK') {
      return RutaResultado(
        destino: destino,
        error: _mensajeEstado(estado, mensajeGoogle),
      );
    }

    final rutas = datos['routes'] as List? ?? const [];
    if (rutas.isEmpty) {
      return RutaResultado(
        destino: destino,
        error: 'Google no encontró una ruta en auto hasta ese punto.',
      );
    }

    final ruta = rutas.first as Map<String, dynamic>;
    final polylines = ruta['overview_polyline'] as Map<String, dynamic>?;
    final puntos = decodificarPolilinea(polylines?['points'] as String? ?? '');

    final tramos = ruta['legs'] as List? ?? const [];
    final instrucciones = <InstruccionRuta>[];
    for (final tramo in tramos) {
      final pasos = (tramo as Map<String, dynamic>)['steps'] as List? ?? const [];
      for (final paso in pasos) {
        final p = paso as Map<String, dynamic>;
        final inicio = p['start_location'] as Map<String, dynamic>?;
        final texto = _limpiarHtml(p['html_instructions'] as String? ?? '');
        if (texto.isEmpty) continue;
        instrucciones.add(InstruccionRuta(
          texto: texto,
          maniobra: p['maneuver'] as String?,
          metros: ((p['distance'] as Map?)?['value'] as num? ?? 0).toInt(),
          inicio: LatLng(
            (inicio?['lat'] as num? ?? destino.latitude).toDouble(),
            (inicio?['lng'] as num? ?? destino.longitude).toDouble(),
          ),
        ));
      }
    }

    if (puntos.length < 2) {
      return RutaResultado(
        destino: destino,
        error: 'Google devolvió una ruta sin recorrido. Inténtalo de nuevo.',
      );
    }

    return RutaResultado(
      puntos: puntos,
      instrucciones: instrucciones,
      distanciaTexto: tramos.isEmpty
          ? ''
          : ((tramos.first as Map<String, dynamic>)['distance'] as Map?)?['text']
                  as String? ??
              '',
      duracionTexto: tramos.isEmpty
          ? ''
          : ((tramos.first as Map<String, dynamic>)['duration'] as Map?)?['text']
                  as String? ??
              '',
      destino: destino,
    );
  }

  static String _mensajeEstado(String estado, String? detalle) {
    switch (estado) {
      case 'ZERO_RESULTS':
        return 'No hay una ruta en auto hasta ese punto. Revisa la ubicación del cliente.';
      case 'NOT_FOUND':
        return 'No se encontró el punto de partida o de llegada.';
      case 'OVER_QUERY_LIMIT':
      case 'OVER_DAILY_LIMIT':
        return 'Se agotó la cuota de Google Maps por hoy. Inténtalo más tarde.';
      case 'REQUEST_DENIED':
        return 'Google rechazó la solicitud: revisa que la clave de Maps y la '
            'Directions API estén habilitadas.';
      case 'INVALID_REQUEST':
        return 'La solicitud de ruta está incompleta.';
      default:
        if (detalle != null && detalle.isNotEmpty) {
          return 'No se pudo calcular la ruta: $detalle';
        }
        return 'No se pudo calcular la ruta en este momento.';
    }
  }

  /// Quita las etiquetas HTML que trae Google y deja una frase natural.
  static String _limpiarHtml(String html) {
    var texto = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    texto = texto
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return texto;
  }

  /// Decodifica el formato "encoded polyline" de Google.
  static List<LatLng> decodificarPolilinea(String codificada) {
    if (codificada.isEmpty) return const [];
    final puntos = <LatLng>[];
    var indice = 0;
    var lat = 0;
    var lng = 0;

    while (indice < codificada.length) {
      var resultado = 0;
      var desplazamiento = 0;
      int byte;
      do {
        byte = codificada.codeUnitAt(indice++) - 63;
        resultado |= (byte & 0x1f) << desplazamiento;
        desplazamiento += 5;
      } while (byte >= 0x20 && indice < codificada.length);
      final deltaLat = (resultado & 1) != 0 ? ~(resultado >> 1) : (resultado >> 1);
      lat += deltaLat;

      resultado = 0;
      desplazamiento = 0;
      do {
        byte = codificada.codeUnitAt(indice++) - 63;
        resultado |= (byte & 0x1f) << desplazamiento;
        desplazamiento += 5;
      } while (byte >= 0x20 && indice < codificada.length);
      final deltaLng = (resultado & 1) != 0 ? ~(resultado >> 1) : (resultado >> 1);
      lng += deltaLng;

      puntos.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return puntos;
  }
}