/// Apertura de mapas y navegación.
///
/// REGLA IMPORTANTE: el destino SIEMPRE son las coordenadas del CLIENTE
/// (`cliente.latitud` / `cliente.longitud`). La ubicación del teléfono
/// representa dónde está el motorizado, nunca adónde debe ir.
library;

import 'package:url_launcher/url_launcher.dart';

/// Abre el mapa del cliente en su coordenada.
Future<bool> abrirMapaCliente({
  required double latitud,
  required double longitud,
  String? etiqueta,
}) async {
  final destino = '$latitud,$longitud';
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$destino'
    '${etiqueta != null && etiqueta.isNotEmpty ? '&query_place_id=${Uri.encodeComponent(etiqueta)}' : ''}',
  );
  return await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Abre la navegación hacia el cliente usando SUS coordenadas.
/// Si no hay coordenadas, se navega por la dirección escrita.
Future<bool> navegarACliente({
  double? latitud,
  double? longitud,
  String? direccion,
}) async {
  final Uri? uri;
  if (latitud != null && longitud != null) {
    uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitud,$longitud&travelmode=driving',
    );
  } else if (direccion != null && direccion.trim().isNotEmpty) {
    uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${Uri.encodeComponent(direccion.trim())}&travelmode=driving',
    );
  } else {
    uri = null;
  }
  if (uri == null) return false;
  return await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Abre el mapa por dirección escrita (respaldo cuando no hay coordenadas).
Future<bool> abrirMapaPorDireccion(String direccion) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(direccion)}',
  );
  return await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Construye el destino de un cliente a partir de su ficha.
/// Devuelve null si el cliente no tiene coordenadas guardadas.
({double latitud, double longitud})? destinoCliente(Map<String, dynamic> cliente) {
  final lat = (cliente['latitud'] as num?)?.toDouble();
  final lng = (cliente['longitud'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;
  return (latitud: lat, longitud: lng);
}

/// Marca un teléfono para llamar.
Future<bool> llamar(String? telefono) async {
  if (telefono == null || telefono.trim().isEmpty) return false;
  final uri = Uri(scheme: 'tel', path: telefono.replaceAll(RegExp(r'\s'), ''));
  return await launchUrl(uri, mode: LaunchMode.externalApplication);
}
