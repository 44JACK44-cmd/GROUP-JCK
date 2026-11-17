/// Devolución de balones vacíos que el cliente todavía debe.
///
/// Los balones prestados se calculan con `movimiento_bal_on`
/// (entregados − devueltos), la misma fuente que usa ADMIN y la rendición.
/// No se crea ningún pago ni venta ficticia.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/data/clientes_repo.dart';
import '../../core/data/sb.dart';
import '../../core/offline/outbox.dart';
import '../../core/state/bus.dart';
import '../../core/ui/estado_conexion.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class DevolucionBalonPage extends ConsumerStatefulWidget {
  const DevolucionBalonPage({super.key});

  @override
  ConsumerState<DevolucionBalonPage> createState() =>
      _DevolucionBalonPageState();
}

class _DevolucionBalonPageState extends ConsumerState<DevolucionBalonPage> {
  Map<String, int> _pendientes = {};
  Map<String, String> _nombres = {};
  bool _cargando = true;
  final _registrando = <String>{};

  @override
  void initState() {
    super.initState();
    SyncBus.dinero.addListener(_onBus);
    _cargar();
  }

  @override
  void dispose() {
    SyncBus.dinero.removeListener(_onBus);
    super.dispose();
  }

  void _onBus() {
    if (mounted) _cargar();
  }

  Future<void> _cargar() async {
    try {
      final res = await Future.wait([
        clientesRepo.saldosBalones(),
        clientesRepo.listar(limite: 500),
      ]);
      if (!mounted) return;
      setState(() {
        _pendientes = res[0] as Map<String, int>;
        _nombres = {
          for (final c in res[1] as List<Map<String, dynamic>>)
            c['id'] as String: c['nombre'] as String? ?? 'Cliente',
        };
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(traducirError(e, contexto: 'No pudimos cargar balones').mensaje),
        ),
      );
    }
  }

  Future<void> _devolver(String clienteId, int cantidad) async {
    if (_registrando.contains(clienteId)) return;
    setState(() => _registrando.add(clienteId));
    final auth = ref.read(authProvider);
    final movimiento = <String, dynamic>{
      'empresa_id': auth.empresaId,
      'cliente_id': clienteId,
      'tipo': 'DEVOLUCION_VACIO',
      'cantidad': cantidad,
      'usuario_id': auth.usuarioId,
      'uuid_offline': const Uuid().v4(),
    };
    try {
      await sb.from('movimiento_bal_on').insert(movimiento);
      SyncBus.dineroCambio();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Devolución registrada.')),
        );
      }
    } catch (e) {
      if (esErrorDeRed(e)) {
        await Outbox.encolarDevolucion(movimiento: movimiento);
        SyncBus.dineroCambio();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Guardado en el dispositivo. Se sincronizará solo.'),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(traducirError(e, contexto: 'No pudimos registrar').mensaje),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _registrando.remove(clienteId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deudores = _pendientes.entries.where((e) => e.value > 0).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Devolución de balones')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            const EstadoConexion(),
            const Text(
              'Balones vacíos que los clientes todavía deben devolver.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              )
            else if (deudores.isEmpty)
              const EstadoVacio(
                icono: Icons.local_fire_department_outlined,
                titulo: 'Todos los balones están devueltos',
              )
            else
              for (final e in deudores)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppTheme.warning.withValues(alpha: 0.12),
                          child: const Icon(Icons.local_fire_department_outlined,
                              color: AppTheme.warning, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_nombres[e.key] ?? 'Cliente',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('Debe ${e.value} balón(es) vacío(s)',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: _registrando.contains(e.key)
                              ? null
                              : () => _devolver(e.key, 1),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            minimumSize: const Size(88, 44),
                          ),
                          child: _registrando.contains(e.key)
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Devuelve 1'),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
