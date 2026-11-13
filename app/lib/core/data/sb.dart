/// Cliente de Supabase compartido y traducción de errores a lenguaje claro.
library;

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get sb => Supabase.instance.client;

/// Errores de PostgreSQL que la app translate a mensajes comprensibles.
class ErrorApp {
  final String mensaje;
  final bool esRed;

  const ErrorApp(this.mensaje, {this.esRed = false});
}

/// Convierte cualquier excepción en un mensaje que el usuario entienda.
/// Nunca se muestran errores técnicos.
ErrorApp traducirError(Object e, {String? contexto}) {
  final prefijo = contexto == null ? '' : '$contexto: ';
  if (e is PostgrestException) {
    final code = e.code;
    switch (code) {
      case '42501':
        return ErrorApp('${prefijo}no tienes permiso para esta operación.');
      case '23505':
        return ErrorApp('${prefijo}este registro ya existe.');
      case '23503':
        return ErrorApp('${prefijo}el registro relacionado ya no existe.');
      case '23514':
        return ErrorApp('${prefijo}el valor enviado no es válido.');
      case '23502':
        return ErrorApp('${prefijo}falta completar un dato obligatorio.');
      case '40001':
      case '40P01':
        return ErrorApp('${prefijo}se cortó la conexión. Inténtalo de nuevo.');
      case 'PGRST116':
        return ErrorApp('${prefijo}no se encontró el registro.');
    }
    final msg = e.message.toLowerCase();
    if (msg.contains('duplicate key')) {
      return ErrorApp('${prefijo}este registro ya existe.');
    }
    if (msg.contains('row-level security')) {
      return ErrorApp('${prefijo}no tienes permiso para esta operación.');
    }
    if (msg.contains('violates check constraint')) {
      return ErrorApp('${prefijo}el valor enviado no es válido.');
    }
    return ErrorApp('${prefijo}no pudimos completar la operación. Inténtalo de nuevo.');
  }
  if (e is AuthException) {
    return ErrorApp('${prefijo}tu sesión expiró. Vuelve a iniciar sesión.');
  }
  if (e is FunctionException) {
    final details = e.details?.toString() ?? '';
    final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(details);
    if (match != null) return ErrorApp('${prefijo}${match.group(1)}');
    return ErrorApp('${prefijo}no pudimos completar la operación. Inténtalo de nuevo.');
  }
  if (e is SocketException || e is HttpException) {
    return ErrorApp('${prefijo}sin conexión. Revisa tu Internet.', esRed: true);
  }
  return ErrorApp('${prefijo}no pudimos completar la operación. Inténtalo de nuevo.');
}

/// True si el error parece ser de red (para Offers: cola offline).
bool esErrorDeRed(Object e) {
  if (e is PostgrestException) {
    final code = e.code;
    if (code == '40001' || code == '40P01' || code == '08006' || code == '08003') return true;
    final msg = e.message.toLowerCase();
    if (msg.contains('failed to fetch') ||
        msg.contains('connection') ||
        msg.contains('timeout') ||
        msg.contains('network')) {
      return true;
    }
    return false;
  }
  if (e is SocketException || e is HttpException) return true;
  return false;
}
