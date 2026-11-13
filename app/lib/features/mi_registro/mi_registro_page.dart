/// "Mi registro": cuaderno digital del motorizado.
///
/// Permite registrar pedidos que se tomaron fuera de la aplicación,
/// gastos e incidencias durante la jornada. Todo queda asociado al
/// motorizado y a su empresa, y aparece en la rendición del día.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../auth/auth_controller.dart';

class MiRegistroPage extends ConsumerStatefulWidget {
  const MiRegistroPage({super.key});

  @override
  ConsumerState<MiRegistroPage> createState() => _MiRegistroPageState();
}

class _MiRegistroPageState extends ConsumerState<MiRegistroPage> {
  List<Map<String, dynamic>> _registros = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final auth = ref.read(authProvider);
    if (auth.usuarioId == null) return;
    try {
      // Pedidos registrados por el motorizado hoy
      final inicio = inicioHoy();
      final fin = DateTime.now().add(const Duration(minutes: 1));
      final pedidos = await pedidosRepo.listar(
        repartidorId: auth.usuarioId,
        desde: inicio,
        hasta: fin,
        limite: 200,
      );
      // Filtrar solo los de origen MOTORIZADO
      final manuales = pedidos.where((p) => p['origen'] == 'MOTORIZADO').toList();

      // Gastos del motorizado hoy
      final gastos = await sb
          .from('gastos')
          .select('id, descripcion, monto, categoria, fecha')
          .eq('usuario_id', auth.usuarioId!)
          .gte('fecha', inicio.toIso8601String())
          .lte('fecha', fin.toIso8601String())
          .order('fecha', ascending: false)
          .limit(100);

      // Incidencias del motorizado hoy
      final incidencias = await sb
          .from('incidencias')
          .select('id, tipo, descripcion, monto, fecha')
          .eq('usuario_id', auth.usuarioId!)
          .gte('fecha', inicio.toIso8601String())
          .lte('fecha', fin.toIso8601String())
          .order('fecha', ascending: false)
          .limit(100);

      if (!mounted) return;
      final lista = <Map<String, dynamic>>[];

      for (final p in manuales) {
        lista.add({
          'tipo': 'PEDIDO',
          'hora': parseFecha(p['fecha']),
          'descripcion': 'Pedido #${p['numero']} — ${dinero((p['total'] as num? ?? 0).toDouble())}',
          'monto': (p['total'] as num? ?? 0).toDouble(),
          'icono': Icons.receipt_long_outlined,
          'color': AppTheme.primary,
        });
      }
      for (final g in gastos) {
        lista.add({
          'tipo': 'GASTO',
          'hora': parseFecha(g['fecha'] as String?),
          'descripcion': '${g['categoria'] ?? 'Gasto'} — ${g['descripcion']}',
          'monto': (g['monto'] as num? ?? 0).toDouble(),
          'icono': Icons.payments_outlined,
          'color': AppTheme.warning,
        });
      }
      for (final i in incidencias) {
        lista.add({
          'tipo': 'INCIDENCIA',
          'hora': parseFecha(i['fecha'] as String?),
          'descripcion': '${i['tipo']} — ${i['descripcion']}',
          'monto': (i['monto'] as num? ?? 0).toDouble(),
          'icono': Icons.build_outlined,
          'color': AppTheme.danger,
        });
      }

      lista.sort((a, b) {
        final ha = a['hora'] as DateTime?;
        final hb = b['hora'] as DateTime?;
        if (ha == null || hb == null) return 0;
        return hb.compareTo(ha);
      });

      setState(() {
        _registros = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi registro'),
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
                  // Acciones rápidas
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => context.push('/mi-registro/pedido'),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Pedido'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: AppTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => context.push('/mi-registro/gasto'),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Gasto'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: AppTheme.warning,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => context.push('/mi-registro/incidencia'),
                          icon: const Icon(Icons.build_outlined),
                          label: const Text('Falla'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: AppTheme.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Lo registrado hoy', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_registros.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Nada registrado hoy. Toca un botón de arriba para empezar.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  else
                    for (final r in _registros)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: Icon(r['icono'] as IconData, color: r['color'] as Color),
                            title: Text(r['descripcion'] as String,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              r['hora'] == null
                                  ? ''
                                  : '${(r['hora'] as DateTime).hour.toString().padLeft(2, '0')}:${(r['hora'] as DateTime).minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.black54),
                            ),
                            trailing: (r['monto'] as double) > 0
                                ? Text(dinero(r['monto'] as double),
                                    style: const TextStyle(fontWeight: FontWeight.bold))
                                : null,
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
