/// Historial del motorizado: los pedidos que ya atendió.
///
/// Solo los asignados/atendidos por ese motorizado. Agrupados por día.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';
import 'pedido_detalle_page.dart';

class HistorialPage extends ConsumerStatefulWidget {
  const HistorialPage({super.key});

  @override
  ConsumerState<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends ConsumerState<HistorialPage> {
  List<Map<String, dynamic>> _pedidos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final auth = ref.read(authProvider);
    try {
      final data = await pedidosRepo.listar(
        repartidorId: auth.esAdmin ? null : auth.usuarioId,
        estados: const ['ENTREGADO', 'NO_ENTREGADO'],
        limite: 200,
      );
      if (!mounted) return;
      setState(() {
        _pedidos = data;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _abrir(Map<String, dynamic> pedido) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PedidoDetallePage(pedido: pedido)),
    );
    if (cambio == true) _cargar();
  }

  /// Agrupa los pedidos por día (Hoy, Ayer, fecha).
  Map<String, List<Map<String, dynamic>>> _porDia() {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final p in _pedidos) {
      final fecha = parseFecha(p['fecha']);
      if (fecha == null) continue;
      final dia = fechaRelativa(fecha);
      grupos.putIfAbsent(dia, () => []).add(p);
    }
    return grupos;
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _porDia();
    return Scaffold(
      appBar: AppBar(title: const Text('Mis pedidos realizados')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _pedidos.isEmpty
              ? const EstadoVacio(
                  icono: Icons.history,
                  titulo: 'Todavía no has entregado pedidos',
                  mensaje: 'Aquí verás el historial de tus entregas.',
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      for (final entrada in grupos.entries) ...[
                        Text(entrada.key,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final p in entrada.value)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _FilaHistorial(pedido: p, onTap: () => _abrir(p)),
                          ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _FilaHistorial extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final VoidCallback onTap;

  const _FilaHistorial({required this.pedido, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cliente = pedido['clientes'] as Map<String, dynamic>?;
    final estado = pedido['estado'] as String? ?? '';
    final entregado = estado == 'ENTREGADO';
    final forma = pedido['forma_pago'] as String?;
    final total = (pedido['total'] as num? ?? 0).toDouble();

    return Card(
      child: ListTile(
        leading: Icon(
          entregado ? Icons.check_circle : Icons.report_gmailerrorred_outlined,
          color: entregado ? AppTheme.success : AppTheme.danger,
        ),
        title: Text(
          cliente?['nombre'] as String? ?? 'Cliente',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            '#${pedido['numero']}',
            if (forma != null) metodoPago(forma),
          ].join(' · '),
        ),
        trailing: Text(
          dinero(total),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onTap: onTap,
      ),
    );
  }
}
