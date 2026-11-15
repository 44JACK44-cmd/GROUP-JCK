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

  /// Días de la semana en que trabaja (1=Lunes..7=Domingo).
  /// `null` = todos los días (compatibilidad).
  Future<List<int>?> diasTrabajo(String motorizadoId) async {
    final data = await sb
        .from('perfiles')
        .select('dias_trabajo')
        .eq('id', motorizadoId)
        .maybeSingle();
    final d = data?['dias_trabajo'];
    if (d == null) return null;
    return List<int>.from(d as List);
  }

  Future<void> guardarDiasTrabajo(String motorizadoId, List<int>? dias) async {
    await sb.from('perfiles').update({'dias_trabajo': dias}).eq('id', motorizadoId);
  }

  /// ¿El motorizado trabaja el día indicado (1=Lunes..7=Domingo)?
  bool trabajaHoy(List<int>? dias, int diaSemana) {
    if (dias == null || dias.isEmpty) return true;
    return dias.contains(diaSemana);
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
