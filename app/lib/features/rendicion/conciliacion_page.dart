/// Conciliación: comparación de pedidos de recepción vs motorizado.
///
/// El admin ve qué pedidos registró recepción, qué registró el motorizado,
/// y las diferencias entre ambos.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/domain/formato.dart';

class ConciliacionPage extends ConsumerStatefulWidget {
  const ConciliacionPage({super.key});

  @override
  ConsumerState<ConciliacionPage> createState() => _ConciliacionPageState();
}

class _ConciliacionPageState extends ConsumerState<ConciliacionPage> {
  List<Map<String, dynamic>> _pedidosAdmin = [];
  List<Map<String, dynamic>> _pedidosMoto = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final inicio = inicioHoy();
      final fin = DateTime.now().add(const Duration(minutes: 1));
      final todos = await pedidosRepo.listar(desde: inicio, hasta: fin, limite: 500);
      if (!mounted) return;
      final admin = todos.where((p) => p['origen'] != 'MOTORIZADO').toList();
      final moto = todos.where((p) => p['origen'] == 'MOTORIZADO').toList();
      setState(() {
        _pedidosAdmin = admin;
        _pedidosMoto = moto;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAdmin = _pedidosAdmin.fold<double>(0, (s, p) => s + ((p['total'] as num? ?? 0).toDouble()));
    final totalMoto = _pedidosMoto.fold<double>(0, (s, p) => s + ((p['total'] as num? ?? 0).toDouble()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conciliación'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // Resumen
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Resumen del día', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('Recepción', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                                    Text('${_pedidosAdmin.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                    Text(dinero(totalAdmin), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('Motorizado', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                                    Text('${_pedidosMoto.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                    Text(dinero(totalMoto), style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_pedidosAdmin.length != _pedidosMoto.length || (totalAdmin - totalMoto).abs() > 0.009) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Diferencia: ${_pedidosAdmin.length - _pedidosMoto.length} pedido(s), ${dinero((totalAdmin - totalMoto).abs())}',
                                      style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Pedidos de recepción
                  Text('Pedidos de recepción (${_pedidosAdmin.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_pedidosAdmin.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Sin pedidos de recepción hoy.', style: TextStyle(color: Colors.black54)),
                      ),
                    )
                  else
                    for (final p in _pedidosAdmin)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                              child: Text('#${p['numero']}', style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            title: Text((p['clientes'] as Map?)?['nombre'] as String? ?? 'Cliente',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${metodoPago(p['forma_pago'] as String?)} · ${antiguedad(parseFecha(p['fecha']))}',
                              style: const TextStyle(color: Colors.black54, fontSize: 12),
                            ),
                            trailing: Text(dinero((p['total'] as num? ?? 0).toDouble()),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                  const SizedBox(height: 16),
                  // Pedidos del motorizado
                  Text('Pedidos del motorizado (${_pedidosMoto.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_pedidosMoto.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Sin pedidos registrados por motorizados hoy.', style: TextStyle(color: Colors.black54)),
                      ),
                    )
                  else
                    for (final p in _pedidosMoto)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          color: AppTheme.warning.withValues(alpha: 0.05),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.warning.withValues(alpha: 0.12),
                              child: Text('#${p['numero']}', style: const TextStyle(color: AppTheme.warning, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            title: Text((p['clientes'] as Map?)?['nombre'] as String? ?? 'Cliente',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '🟠 Registrado por motorizado · ${metodoPago(p['forma_pago'] as String?)}',
                              style: const TextStyle(color: AppTheme.warning, fontSize: 12),
                            ),
                            trailing: Text(dinero((p['total'] as num? ?? 0).toDouble()),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
