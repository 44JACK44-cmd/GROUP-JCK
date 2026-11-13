/// Informes del administrador.
///
/// Todo sale de los registros reales: pedidos, ventas, pagos, deudas,
/// balones, motorizados y combustible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/informes_repo.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';

/// Periodo del informe.
enum PeriodoInforme {
  hoy('Hoy'),
  semana('Esta semana'),
  mes('Este mes');

  const PeriodoInforme(this.label);

  final String label;
}

class ReportesPage extends ConsumerStatefulWidget {
  const ReportesPage({super.key});

  @override
  ConsumerState<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends ConsumerState<ReportesPage> {
  PeriodoInforme _periodo = PeriodoInforme.hoy;
  InformesResumen _datos = const InformesResumen();
  List<RendimientoMotorizado> _motorizados = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final ahora = DateTime.now();
    final (desde, hasta) = switch (_periodo) {
      PeriodoInforme.hoy => (inicioHoy(ahora), ahora.add(const Duration(minutes: 1))),
      PeriodoInforme.semana => (inicioSemana(ahora), ahora.add(const Duration(minutes: 1))),
      PeriodoInforme.mes => (inicioMes(ahora), ahora.add(const Duration(minutes: 1))),
    };
    try {
      final res = await Future.wait([
        informesRepo.calcular(desde: desde, hasta: hasta),
        informesRepo.porMotorizado(desde: desde, hasta: hasta),
      ]);
      if (!mounted) return;
      setState(() {
        _datos = res[0] as InformesResumen;
        _motorizados = res[1] as List<RendimientoMotorizado>;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                for (final p in PeriodoInforme.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p.label),
                      selected: _periodo == p,
                      selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: _periodo == p ? AppTheme.primary : Colors.black87,
                        fontWeight: _periodo == p ? FontWeight.w600 : FontWeight.normal,
                      ),
                      onSelected: (_) {
                        setState(() => _periodo = p);
                        _cargar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : RefreshIndicator(
                    onRefresh: _cargar,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        _Seccion(
                          titulo: 'Pedidos',
                          filas: [
                            FilaValor('Total', '${d.totalPedidos}'),
                            FilaValor('Pendientes', '${d.pendientes}', color: AppTheme.warning),
                            FilaValor('Entregados', '${d.entregados}', color: AppTheme.success),
                            FilaValor('Cancelados', '${d.cancelados}', color: AppTheme.danger),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Seccion(
                          titulo: 'Ventas',
                          filas: [
                            FilaValor('Total vendido', dinero(d.totalVendido), destacado: true),
                            FilaValor('Cobrado', dinero(d.cobrado), color: AppTheme.success),
                            FilaValor('Pendiente', dinero(d.pendiente),
                                color: d.pendiente > 0 ? AppTheme.danger : null),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Seccion(
                          titulo: 'Pagos',
                          filas: [
                            FilaValor('Efectivo', dinero(d.efectivo)),
                            FilaValor('Yape', dinero(d.yape), color: AppTheme.info),
                            FilaValor('Otros', dinero(d.otros)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Seccion(
                          titulo: 'Deudas',
                          filas: [
                            FilaValor('Clientes deudores', '${d.clientesDeudores}',
                                color: AppTheme.danger),
                            FilaValor('Monto pendiente', dinero(d.totalDeudas),
                                destacado: true),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Seccion(
                          titulo: 'Balones',
                          filas: [
                            FilaValor('Entregados', '${d.balonesEntregados}'),
                            FilaValor('Vacíos recibidos', '${d.balonesVaciosRecibidos}',
                                color: AppTheme.success),
                            FilaValor('Vacíos pendientes', '${d.balonesVaciosPendientes}',
                                color: d.balonesVaciosPendientes > 0 ? AppTheme.warning : null),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Seccion(
                          titulo: 'Gastos',
                          filas: [
                            FilaValor('Gastos', dinero(d.gastos), color: AppTheme.danger),
                            FilaValor('Combustible', dinero(d.combustible),
                                color: AppTheme.danger),
                          ],
                        ),
                        if (_motorizados.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _Seccion(
                            titulo: 'Motorizados',
                            filas: [
                              for (final m in _motorizados)
                                FilaValor(
                                  '${m.nombre} (${m.entregados}/${m.pedidos})',
                                  '${dinero(m.cobrado)}'
                                  '${m.pendiente > 0 ? ' · debe ${dinero(m.pendiente)}' : ''}',
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  final String titulo;
  final List<Widget> filas;

  const _Seccion({required this.titulo, required this.filas});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...filas,
          ],
        ),
      ),
    );
  }
}
