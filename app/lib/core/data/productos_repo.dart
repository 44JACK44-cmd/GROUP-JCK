/// Catálogo de productos.
///
/// Regla de negocio: el **fierro** (soporte) y el **balón vacío** son el MISMO
/// activo retornable. En el catálogo existen una sola vez, con
/// `tipo = 'RETORNABLE'` y precio 0; no se cobran ni generan dinero. Su control
/// real es el saldo de `movimiento_bal_on` / `movimiento_fierro`.
///
/// Las notas u observaciones nunca crean productos ni dinero: este repositorio
/// solo lee el catálogo que el administrador mantiene.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sb.dart';

class ProductosRepo {
  const ProductosRepo();

  /// Columnas que usan todas las pantallas.
  static const _columnas = 'id, nombre, capacidad_kg, precio_base';

  /// Productos que se pueden vender (excluye los activos retornables).
  ///
  /// Si la migración de la columna `tipo` todavía no se aplicó, se devuelve el
  /// catálogo completo y la pantalla sigue funcionando.
  Future<List<Map<String, dynamic>>> vendibles() async {
    try {
      final data = await sb
          .from('productos')
          .select(_columnas)
          .eq('activo', true)
          .neq('tipo', 'RETORNABLE')
          .order('nombre');
      return List<Map<String, dynamic>>.from(data);
    } on PostgrestException catch (e) {
      if (!esColumnaAusente(e)) rethrow;
      final data = await sb
          .from('productos')
          .select(_columnas)
          .eq('activo', true)
          .order('nombre');
      return List<Map<String, dynamic>>.from(data);
    }
  }

  /// El concepto único "Fierro / Balón vacío", si ya existe en la empresa.
  ///
  /// Sirve para mostrarlo como activo retornable y para dejar claro que no se
  /// vende. Nunca se usa para generar una línea de pedido.
  Future<Map<String, dynamic>?> retornable() async {
    try {
      final fila = await sb
          .from('productos')
          .select('id, nombre, tipo')
          .eq('activo', true)
          .eq('tipo', 'RETORNABLE')
          .order('nombre')
          .limit(1)
          .maybeSingle();
      return fila;
    } on PostgrestException catch (e) {
      if (!esColumnaAusente(e)) rethrow;
      return null;
    }
  }
}
