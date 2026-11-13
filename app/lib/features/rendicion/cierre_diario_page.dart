/// Cierre diario de jornada por el administrador.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/rendiciones_repo.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class CierreDiarioPage extends ConsumerStatefulWidget {
  const CierreDiarioPage({super.key});

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

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final auth = ref.read(authProvider);
    try {
      final data = await rendicionesRepo.obtenerCierre(auth.empresaId!, DateTime.now());
      if (!mounted) return;
      setState(() {
        _cierre = data;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _cerrar() async {
    final auth = ref.read(authProvider);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar jornada'),
        content: const Text('¿Estás seguro de cerrar la jornada de hoy? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar')),
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
        const SnackBar(content: Text('Jornada cerrada correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
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
        title: const Text('Cierre diario'),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (cerrado) ...[
                  Card(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: AppTheme.success),
                              const SizedBox(width: 8),
                              Text('Jornada cerrada', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.success)),
                            ],
                          ),
                          const SizedBox(height: 10),
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
                              padding: const EdgeInsets.only(top: 8),
                              child: Text('Obs: ${_cierre!['justificacion']}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cerrar jornada de hoy', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 10),
                          const Text(
                            'Se calcularán automáticamente los totales del día. '
                            'No se puede cerrar si hay rendiciones pendientes de revisión.',
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _justificacionCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Justificación (opcional)',
                              prefixIcon: Icon(Icons.notes_outlined),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _cerrando ? null : _cerrar,
                            icon: const Icon(Icons.lock_outlined),
                            label: Text(_cerrando ? 'Cerrando…' : 'Cerrar jornada'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
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
    );
  }
}
