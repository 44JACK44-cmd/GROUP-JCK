/// Catálogo de productos.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sb.dart';

class ProductosRepo {
  const ProductosRepo();

  static const _columnasConTipo = 'id, nombre, capacidad_kg, precio_base, tipo';
  static const _columnasBase = 'id, nombre, capacidad_kg, precio_base';

  static bool _tipoDisponible = true;

  static bool esVendible(Map<String, dynamic> producto) {
    final tipo = producto['tipo'] as String?;
    if (tipo == null) return true;
    return tipo != 'RETORNABLE';
  }

  Future<List<Map<String, dynamic>>> vendibles() async {
    try {
      final select = _tipoDisponible ? _columnasConTipo : _columnasBase;
      var q = sb.from('productos').select(select).eq('activo', true);
      if (_tipoDisponible) q = q.neq('tipo', 'RETORNABLE');
      final data = await q.order('nombre');
      return List<Map<String, dynamic>>.from(data).where(esVendible).toList();
    } on PostgrestException catch (e) {
      if (!esColumnaAusente(e)) rethrow;
      _tipoDisponible = false;
      final data = await sb
          .from('productos')
          .select(_columnasBase)
          .eq('activo', true)
          .order('nombre');
      return List<Map<String, dynamic>>.from(data);
    }
  }

  Future<Map<String, dynamic>?> retornable() async {
    if (!_tipoDisponible) return null;
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
      _tipoDisponible = false;
      return null;
    }
  }
}
