import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';

/// Resumen del negocio: ventas, cobros, gastos y pedidos del día y la semana.
class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  bool _cargando = true;
  Map<String, dynamic> _hoy = {};
  Map<String, dynamic> _semana = {};

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final ahora = DateTime.now();
      final inicioHoy = DateTime(ahora.year, ahora.month, ahora.day).toIso8601String();
      final inicioSemana = DateTime(ahora.year, ahora.month, ahora.day)
          .subtract(const Duration(days: 7))
          .toIso8601String();

      Future<List<dynamic>> q(String tabla, String desde) => _sb
          .from(tabla)
          .select()
          .gte('fecha', desde);

      final resultados = await Future.wait([
        q('pedidos', inicioHoy),
        q('pagos', inicioHoy),
        q('gastos', inicioHoy),
        q('pedidos', inicioSemana),
        q('pagos', inicioSemana),
        q('gastos', inicioSemana),
      ]);

      if (!mounted) return;
      setState(() {
        _hoy = _resumir(resultados[0], resultados[1], resultados[2]);
        _semana = _resumir(resultados[3], resultados[4], resultados[5]);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos cargar los reportes.')),
      );
    }
  }

  Map<String, dynamic> _resumir(List<dynamic> pedidos, List<dynamic> pagos, List<dynamic> gastos) {
    double ventas = 0, cobros = 0, gastosT = 0;
    var entregados = 0, pendientes = 0;
    for (final p in pedidos) {
      final m = p as Map<String, dynamic>;
      if (m['estado'] == 'ENTREGADO') {
        ventas += (m['total'] as num? ?? 0).toDouble();
        entregados++;
      } else if (m['estado'] != 'CANCELADO') {
        pendientes++;
      }
    }
    for (final p in pagos) {
      cobros += (p as Map<String, dynamic>)['monto'] as num? ?? 0;
    }
    for (final g in gastos) {
      gastosT += (g as Map<String, dynamic>)['monto'] as num? ?? 0;
    }
    return {
      'ventas': ventas,
      'cobros': cobros,
      'gastos': gastosT,
      'entregados': entregados,
      'pendientes': pendientes,
      'pedidos': pedidos.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Seccion(titulo: 'Hoy', datos: _hoy),
                  const SizedBox(height: 16),
                  _Seccion(titulo: 'Últimos 7 días', datos: _semana),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _Seccion extends StatelessWidget {
  final String titulo;
  final Map<String, dynamic> datos;
  const _Seccion({required this.titulo, required this.datos});

  @override
  Widget build(BuildContext context) {
    double d(String k) => (datos[k] as num? ?? 0).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _Fila('Ventas entregadas', 'S/ ${d('ventas').toStringAsFixed(2)}',
                color: AppTheme.success),
            _Fila('Cobros', 'S/ ${d('cobros').toStringAsFixed(2)}', color: AppTheme.info),
            _Fila('Gastos', 'S/ ${d('gastos').toStringAsFixed(2)}', color: AppTheme.danger),
            const Divider(height: 20),
            _Fila('Ganancia aprox.',
                'S/ ${(d('ventas') - d('gastos')).toStringAsFixed(2)}',
                destacado: true),
            _Fila('Pedidos entregados', '${datos['entregados'] ?? 0}'),
            _Fila('Pedidos pendientes', '${datos['pendientes'] ?? 0}'),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String label;
  final String valor;
  final Color? color;
  final bool destacado;

  const _Fila(this.label, this.valor, {this.color, this.destacado = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
              color: destacado ? Colors.black : Colors.black54,
              fontWeight: destacado ? FontWeight.bold : FontWeight.normal)),
          Text(valor, style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? (destacado ? AppTheme.primary : Colors.black87))),
        ],
      ),
    );
  }
}
