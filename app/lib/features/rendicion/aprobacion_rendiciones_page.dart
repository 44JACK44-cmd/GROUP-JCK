/// Aprobación de rendiciones por el administrador.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/data/rendiciones_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../auth/auth_controller.dart';

class AprobacionRendicionesPage extends ConsumerStatefulWidget {
  AprobacionRendicionesPage({super.key});

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
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(traducirError(e, contexto: 'No pudimos cargar las rendiciones').mensaje),
        ),
      );
    }
  }

  Future<void> _revisar(Map<String, dynamic> rendicion, String estado) async {
    final justificacion = await _pedirJustificacion(estado);
    // Si el admin cancela el diálogo, NO se aprueba ni se observa nada.
    if (justificacion == null) return;

    final auth = ref.read(authProvider);
    try {
      // La diferencia se calcula con la fecha real de la rendición (no con las
      // últimas 24 h) y descontando los gastos de cada bolsillo.
      final motorizadoId = rendicion['motorizado_id'] as String;
      final fechaRendicion =
          DateTime.tryParse(rendicion['fecha']?.toString() ?? '') ?? DateTime.now();
      final inicio = DateTime(
        fechaRendicion.year,
        fechaRendicion.month,
        fechaRendicion.day,
      );
      final fin = inicio.add(Duration(days: 1));
      final r = await rendicionRepo.calcular(
        desde: inicio,
        hasta: fin,
        motorizadoId: motorizadoId,
      );
      final esperado =
          (r.efectivo - r.gastosEfectivo) + (r.yape - r.gastosYape);
      final declarado = (rendicion['efectivo_declarado'] as num? ?? 0).toDouble() +
          (rendicion['yape_declarado'] as num? ?? 0).toDouble();
      // Positivo = falta dinero; negativo = sobra.
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
        SnackBar(
          content: Text(traducirError(e, contexto: 'No se pudo revisar').mensaje),
        ),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text('Confirmar')),
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
        return AppColors.textoSecundario;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rendiciones'),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: _cargar, icon: Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _rendiciones.isEmpty
              ? Center(child: Text('No hay rendiciones registradas.', style: TextStyle(color: AppColors.textoSecundario)))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: _rendiciones.length,
                    itemBuilder: (context, i) {
                      final r = _rendiciones[i];
                      final motorizado = r['perfiles'] as Map<String, dynamic>?;
                      final estado = r['estado'] as String? ?? 'PENDIENTE';
                      return Card(
                        margin: EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      motorizado?['nombre'] as String? ?? 'Motorizado',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                              SizedBox(height: 8),
                              Text('Fecha: ${r['fecha']}', style: TextStyle(color: AppColors.textoSecundario, fontSize: 13)),
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
                                Text('Obs: ${r['observaciones']}', style: TextStyle(color: AppColors.textoSecundario, fontSize: 12)),
                              SizedBox(height: 10),
                              if (estado == 'PENDIENTE' || estado == 'EN_REVISION') ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => _revisar(r, EstadoRendicion.aprobada),
                                        icon: Icon(Icons.check, size: 18),
                                        label: Text('Aprobar'),
                                        style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _revisar(r, EstadoRendicion.observada),
                                        icon: Icon(Icons.warning_amber, size: 18, color: AppTheme.warning),
                                        label: Text('Observar', style: TextStyle(color: AppTheme.warning)),
                                        style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.warning)),
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