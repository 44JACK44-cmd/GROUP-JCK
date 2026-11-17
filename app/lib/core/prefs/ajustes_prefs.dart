/// Preferencias locales del dispositivo.
///
/// Se guardan solo en el teléfono (nunca en la nube) y no contienen secretos.
/// Viven aquí, y no en la pantalla de Ajustes, para que las use también el
/// mapa y el asistente de voz.
library;

import 'package:shared_preferences/shared_preferences.dart';

class AjustesPrefs {
  AjustesPrefs._();

  static const _kMapaInterno = 'ajustes_mapa_dentro_app';
  static const _kAudio = 'ajustes_asistente_voz';

  /// Abrir el mapa dentro de la app (en vez de saltar a Google Maps).
  static Future<bool> mapaDentroDeApp() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kMapaInterno) ?? true;
  }

  static Future<void> setMapaDentroDeApp(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kMapaInterno, v);
  }

  /// Asistente de voz con las indicaciones de la ruta.
  static Future<bool> asistenteDeVoz() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAudio) ?? true;
  }

  static Future<void> setAsistenteDeVoz(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAudio, v);
  }
}