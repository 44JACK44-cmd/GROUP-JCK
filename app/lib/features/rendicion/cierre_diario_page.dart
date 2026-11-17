/// Cierre diario de jornada por el administrador.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/rendiciones_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class CierreDiarioPage extends ConsumerStatefulWidget {
  CierreDiarioPage({super.key});

  @override
  ConsumerState<CierreDiarioPage> createState() => _CierreDiarioPageState();
}

class _CierreDiarioPageState extends ConsumerState<CierreDiarioPage> {
  Map<String, dynamic>? _cierre;
  bool _cargando = true;
  bool _cerrando = false;
  final _justificacionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _justificacionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _cargando = true);
    final auth = ref.read(authProvider);
    try {
      final data = await rendicionesRepo.obtenerCierre(auth.empresaId!, DateTime.now());
      if (!mounted) return;
      setState(() {
        _cierre = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            traducirError(e, contexto: 'No pudimos cargar el cierre').mensaje,
          ),
        ),
      );
    }
  }

  Future<void> _cerrar() async {
    final auth = ref.read(authProvider);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cerrar jornada'),
        content: Text('¿Estás seguro de cerrar la jornada de hoy? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Cerrar')),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _cerrando = true);
    try {
      await rendicionesRepo.cerrarJornada(
        empresaId: auth.empresaId!,
        adminId: auth.usuarioId!,
        fecha: DateTime.now(),
        observaciones: _justificacionCtrl.text.trim().isEmpty ? null : _justificacionCtrl.text.trim(),
      );
      if (!mounted) return;
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Jornada cerrada correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            traducirError(e, contexto: 'No pudimos cerrar la jornada').mensaje,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _cerrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cerrado = _cierre != null && _cierre!['estado'] == 'CERRADO';

    return Scaffold(
      appBar: AppBar(
        title: Text('Cierre diario'),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: _cargar, icon: Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: () => _cargar(silencioso: true),
              child: ListView(
                physics: AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(16),
                children: [
                if (cerrado) ...[
                  Card(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_circle, color: AppTheme.success),
                              SizedBox(width: 8),
                              Text('Jornada cerrada', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.success)),
                            ],
                          ),
                          SizedBox(height: 10),
                          FilaValor('Total ventas', dinero((_cierre!['total_ventas'] as num? ?? 0).toDouble())),
                          FilaValor('Efectivo esperado', dinero((_cierre!['efectivo_esperado'] as num? ?? 0).toDouble())),
                          FilaValor('Efectivo recibido', dinero((_cierre!['efectivo_recibido'] as num? ?? 0).toDouble())),
                          FilaValor('Yape total', dinero((_cierre!['yape_total'] as num? ?? 0).toDouble())),
                          FilaValor('Deudas', dinero((_cierre!['deudas_total'] as num? ?? 0).toDouble())),
                          FilaValor('Gastos', dinero((_cierre!['gastos_total'] as num? ?? 0).toDouble())),
                          FilaValor('Pedidos pendientes', '${_cierre!['pedidos_pendientes']}'),
                          FilaValor('Rendiciones pendientes', '${_cierre!['rendiciones_pendientes']}'),
                          if (_cierre!['justificacion'] != null)
                            Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('Obs: ${_cierre!['justificacion']}', style: TextStyle(color: AppColors.textoSecundario, fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cerrar jornada de hoy', style: Theme.of(context).textTheme.titleMedium),
                          SizedBox(height: 10),
                          Text(
                            'Se calcularán automáticamente los totales del día. '
                            'No se puede cerrar si hay rendiciones pendientes de revisión.',
                            style: TextStyle(color: AppColors.textoSecundario),
                          ),
                          SizedBox(height: 14),
                          TextFormField(
                            controller: _justificacionCtrl,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: 'Justificación (opcional)',
                              prefixIcon: Icon(Icons.notes_outlined),
                            ),
                          ),
                          SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _cerrando ? null : _cerrar,
                            icon: Icon(Icons.lock_outlined),
                            label: Text(_cerrando ? 'Cerrando…' : 'Cerrar jornada'),
                            style: FilledButton.styleFrom(
                              minimumSize: Size.fromHeight(52),
                              backgroundColor: AppTheme.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
              ),
            ),
    );
  }
}