/// Asistente de voz en español.
///
/// Regla: solo se dice lo que viene de la ruta real de Google (texto y
/// distancia). Nunca se inventan indicaciones ni se habla si no hay ruta.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../prefs/ajustes_prefs.dart';

class VozService {
  VozService._();

  static final VozService instance = VozService._();

  final FlutterTts _tts = FlutterTts();
  bool _preparado = false;

  /// `null` = todavía no se comprobó; `false` = este teléfono no tiene voz.
  bool? _disponible;

  bool _hablando = false;
  bool get hablando => _hablando;

  /// True si el teléfono puede hablar y el usuario no lo desactivó.
  Future<bool> disponible() async {
    if (!await AjustesPrefs.asistenteDeVoz()) return false;
    await _preparar();
    return _disponible ?? false;
  }

  Future<void> _preparar() async {
    if (_preparado) return;
    _preparado = true;
    try {
      // Español de Perú; si el teléfono no lo tiene, español general.
      var ok = await _tts.setLanguage('es-PE');
      if (ok != 1) ok = await _tts.setLanguage('es-ES');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      _tts.setStartHandler(() => _hablando = true);
      _tts.setCompletionHandler(() => _hablando = false);
      _tts.setCancelHandler(() => _hablando = false);
      _tts.setErrorHandler((_) => _hablando = false);
      final idiomas = await _tts.getLanguages;
      if (ok == 1 && idiomas is List && idiomas.isNotEmpty) {
        _disponible = true;
      } else {
        _disponible = ok == 1;
      }
    } catch (e) {
      debugPrint('Voz no disponible: $e');
      _disponible = false;
    }
  }

  /// Lee en voz alta un texto real (por ejemplo una indicación de Google).
  Future<void> hablar(String texto) async {
    final limpio = texto.trim();
    if (limpio.isEmpty) return;
    if (!await disponible()) return;
    try {
      await _tts.stop();
      await _tts.speak(limpio);
    } catch (e) {
      debugPrint('No se pudo hablar: $e');
    }
  }

  Future<void> detener() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Nada que hacer: el teléfono no tiene voz.
    }
    _hablando = false;
  }
}