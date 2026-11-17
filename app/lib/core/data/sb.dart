/// Cliente de Supabase compartido y traducción de errores a lenguaje claro.
library;

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get sb => Supabase.instance.client;

/// Errores de PostgreSQL que la app translate a mensajes comprensibles.
class ErrorApp {
  final String mensaje;
  final bool esRed;

  ErrorApp(this.mensaje, {this.esRed = false});
}

/// Convierte cualquier excepción en un mensaje que el usuario entienda.
/// Nunca se muestran errores técnicos.
ErrorApp traducirError(Object e, {String? contexto}) {
  final prefijo = contexto == null ? '' : '$contexto: ';
  if (e is PostgrestException) {
    final code = e.code;
    switch (code) {
      case '42501':
        return ErrorApp(
          '${prefijo}la base de datos rechazó el permiso. '
          'Falta aplicar el paso 15 (supabase/steps/v7_15_flujo_simple.sql) '
          'en Supabase → SQL Editor.',
        );
      case '42703':
        return ErrorApp(
          '${prefijo}falta una columna en la base de datos. '
          'Aplica el paso 15 (v7_15_flujo_simple.sql) en Supabase → SQL Editor.',
        );
      case '42P01':
        return ErrorApp(
          '${prefijo}falta una tabla en la base de datos. '
          'Aplica el paso 15 (v7_15_flujo_simple.sql) en Supabase → SQL Editor.',
        );
      case 'PGRST205':
        return ErrorApp(
          '${prefijo}la tabla todavía no existe en Supabase. '
          'Aplica el paso 15 (v7_15_flujo_simple.sql) en el SQL Editor.',
        );
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
    if (msg.contains('row-level security') || msg.contains('permission denied')) {
      return ErrorApp(
        '${prefijo}la base de datos rechazó el permiso. '
        'Aplica el paso 15 (v7_15_flujo_simple.sql) en Supabase → SQL Editor.',
      );
    }
    if (msg.contains('does not exist') ||
        msg.contains('could not find the table') ||
        msg.contains('could not find the function')) {
      return ErrorApp(
        '${prefijo}la base de datos está incompleta. '
        'Aplica el paso 15 (v7_15_flujo_simple.sql) en Supabase → SQL Editor.',
      );
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

/// True si el error indica que la función RPC todavía no existe en la base
/// de datos (migración pendiente). Permite degradar a la ruta antigua sin
/// romper la pantalla.
bool esFuncionAusente(Object e) {
  if (e is PostgrestException) {
    return e.code == '42883' ||
        e.code == 'PGRST202' ||
        e.message.contains('Could not find the function');
  }
  if (e is FunctionException) {
    return (e.details?.toString() ?? '').contains('Could not find the function');
  }
  return false;
}

/// True si el error indica que una columna todavía no existe en la base
/// (migración pendiente). PostgREST usa PGRST204 al insertar y PostgreSQL 42703.
bool esColumnaAusente(Object e) {
  if (e is PostgrestException) {
    return e.code == '42703' ||
        e.code == 'PGRST204' ||
        e.message.contains("Could not find the '");
  }
  return false;
}

/// True si el error indica que una tabla todavía no existe en la base
/// (migración pendiente). PostgreSQL usa 42P01 y PostgREST PGRST205.
bool esTablaAusente(Object e) {
  if (e is PostgrestException) {
    return e.code == '42P01' ||
        e.code == 'PGRST205' ||
        e.message.contains('Could not find the table');
  }
  return false;
}

/// True si un CHECK de la base rechazó el valor (p. ej. forma de pago no
/// permitida porque la migración no está aplicada).
bool esValorInvalido(Object e) {
  if (e is PostgrestException) {
    return e.code == '23514' ||
        e.message.toLowerCase().contains('check constraint');
  }
  return false;
}

/// True si la base rechazó la operación por permisos (RLS).
///
/// Sirve para explicar en lenguaje claro que una función todavía no está
/// habilitada, en vez de mostrar un error técnico.
bool esPermisoDenegado(Object e) {
  if (e is PostgrestException) {
    return e.code == '42501' ||
        e.message.toLowerCase().contains('row-level security') ||
        e.message.toLowerCase().contains('permission denied');
  }
  return false;
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