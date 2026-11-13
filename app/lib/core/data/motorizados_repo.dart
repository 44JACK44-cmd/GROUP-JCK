/// Repositorio de motorizados y vehículos.
library;

import 'sb.dart';

class MotorizadosRepo {
  const MotorizadosRepo();

  /// Motorizados de la empresa (RLS ya limita a los de su empresa).
  Future<List<Map<String, dynamic>>> listar({bool soloActivos = true}) async {
    var q = sb.from('perfiles').select('id, nombre, telefono, activo, rol, empresa_id');
    q = q.eq('rol', 'MOTORIZADO');
    if (soloActivos) q = q.eq('activo', true);
    final data = await q.order('nombre');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> vehiculos({bool soloActivos = true}) async {
    var q = sb.from('vehiculos').select('id, nombre, placa, repartidor_id');
    if (soloActivos) q = q.eq('activo', true);
    final data = await q.order('nombre');
    return List<Map<String, dynamic>>.from(data);
  }

  /// Vehículo asignado a un motorizado (si tiene).
  Future<String?> vehiculoDe(String motorizadoId) async {
    final data = await sb
        .from('vehiculos')
        .select('id, nombre')
        .eq('repartidor_id', motorizadoId)
        .limit(1)
        .maybeSingle();
    return data?['nombre'] as String?;
  }
}

const motorizadosRepo = MotorizadosRepo();
