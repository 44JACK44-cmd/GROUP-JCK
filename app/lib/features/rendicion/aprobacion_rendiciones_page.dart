/// Aprobación de rendiciones por el administrador.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/data/rendiciones_repo.dart';
import '../../core/domain/formato.dart';
import '../auth/auth_controller.dart';

class AprobacionRendicionesPage extends ConsumerStatefulWidget {
  const AprobacionRendicionesPage({super.key});

  @override
  ConsumerState<AprobacionRendicionesPage> createState() => _AprobacionRendicionesPageState();
}

class _AprobacionRendicionesPageState extends ConsumerState<AprobacionRendicionesPage> {
  List<Map<String, dynamic>> _rendiciones = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final data = await rendicionesRepo.listar();
      if (!mounted) return;
      setState(() {
        _rendiciones = data;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _revisar(Map<String, dynamic> rendicion, String estado) async {
    final justificacion = await _pedirJustificacion(estado);
    if (justificacion == null && estado != EstadoRendicion.aprobada) return;

    final auth = ref.read(authProvider);
    try {
      // Calcular diferencia
      final motorizadoId = rendicion['motorizado_id'] as String;
      final inicio = DateTime.now().subtract(const Duration(days: 1));
      final fin = DateTime.now().add(const Duration(minutes: 1));
      final r = await rendicionRepo.calcular(desde: inicio, hasta: fin, motorizadoId: motorizadoId);
      final esperado = r.efectivo + r.yape;
      final declarado = (rendicion['efectivo_declarado'] as num? ?? 0).toDouble() +
          (rendicion['yape_declarado'] as num? ?? 0).toDouble();
      final diferencia = esperado - declarado;

      await rendicionesRepo.revisar(
        empresaId: auth.empresaId!,
        rendicionId: rendicion['id'] as String,
        estado: estado,
        adminId: auth.usuarioId!,
        justificacion: justificacion,
        diferencia: diferencia,
      );
      _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rendición $estado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<String?> _pedirJustificacion(String estado) async {
    final ctrl = TextEditingController();
    final resultado = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(estado == EstadoRendicion.aprobada ? 'Aprobar rendición' : 'Observar rendición'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: estado == EstadoRendicion.aprobada ? 'Observaciones (opcional)' : 'Justificación *',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Confirmar')),
        ],
      ),
    );
    ctrl.dispose();
    if (resultado == null) return null;
    if (estado != EstadoRendicion.aprobada && resultado.isEmpty) return null;
    return resultado;
  }

  Color _colorEstado(String? estado) {
    switch (estado) {
      case 'APROBADA':
        return AppTheme.success;
      case 'CON_DIFERENCIA':
        return AppTheme.danger;
      case 'OBSERVADA':
        return AppTheme.warning;
      case 'EN_REVISION':
        return AppTheme.info;
      default:
        return Colors.black54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rendiciones'),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _rendiciones.isEmpty
              ? const Center(child: Text('No hay rendiciones registradas.', style: TextStyle(color: Colors.black54)))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rendiciones.length,
                    itemBuilder: (context, i) {
                      final r = _rendiciones[i];
                      final motorizado = r['perfiles'] as Map<String, dynamic>?;
                      final estado = r['estado'] as String? ?? 'PENDIENTE';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      motorizado?['nombre'] as String? ?? 'Motorizado',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _colorEstado(estado).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      estado,
                                      style: TextStyle(color: _colorEstado(estado), fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text('Fecha: ${r['fecha']}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                              Text('Efectivo declarado: ${dinero((r['efectivo_declarado'] as num? ?? 0).toDouble())}'),
                              Text('Yape declarado: ${dinero((r['yape_declarado'] as num? ?? 0).toDouble())}'),
                              if ((r['diferencia'] as num? ?? 0).toDouble() != 0)
                                Text(
                                  'Diferencia: ${dinero((r['diferencia'] as num? ?? 0).toDouble())}',
                                  style: TextStyle(
                                    color: (r['diferencia'] as num? ?? 0).toDouble() > 0 ? AppTheme.danger : AppTheme.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (r['observaciones'] != null)
                                Text('Obs: ${r['observaciones']}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                              const SizedBox(height: 10),
                              if (estado == 'PENDIENTE' || estado == 'EN_REVISION') ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => _revisar(r, EstadoRendicion.aprobada),
                                        icon: const Icon(Icons.check, size: 18),
                                        label: const Text('Aprobar'),
                                        style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _revisar(r, EstadoRendicion.observada),
                                        icon: const Icon(Icons.warning_amber, size: 18, color: AppTheme.warning),
                                        label: const Text('Observar', style: TextStyle(color: AppTheme.warning)),
                                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.warning)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
