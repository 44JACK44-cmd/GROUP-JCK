/// Rendición de cuentas por motorizado.
///
/// El admin elige el periodo y el motorizado, y ve los números reales:
/// pedidos, cobros, deudas y balones.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';

/// Periodos disponibles.
enum PeriodoRendicion {
  hoy('Hoy'),
  ayer('Ayer'),
  semana('Esta semana'),
  mes('Este mes'),
  personalizado('Personalizado');

  const PeriodoRendicion(this.label);

  final String label;
}

class RendicionPage extends ConsumerStatefulWidget {
  const RendicionPage({super.key});

  @override
  ConsumerState<RendicionPage> createState() => _RendicionPageState();
}

class _RendicionPageState extends ConsumerState<RendicionPage> {
  PeriodoRendicion _periodo = PeriodoRendicion.hoy;
  DateTime? _desde;
  DateTime? _hasta;
  List<Map<String, dynamic>> _motorizados = [];
  String? _motorizadoId;
  Rendicion _rendicion = const Rendicion();
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarMotorizados();
    _cargar();
  }

  Future<void> _cargarMotorizados() async {
    try {
      final data = await motorizadosRepo.listar(soloActivos: false);
      if (!mounted) return;
      setState(() => _motorizados = data);
    } catch (_) {
      // Sin lista de motorizados: se muestra la rendición de la empresa.
    }
  }

  (DateTime, DateTime) _rango() {
    final ahora = DateTime.now();
    switch (_periodo) {
      case PeriodoRendicion.hoy:
        return (inicioHoy(ahora), ahora.add(const Duration(minutes: 1)));
      case PeriodoRendicion.ayer:
        final ayer = inicioHoy(ahora).subtract(const Duration(days: 1));
        return (ayer, ayer.add(const Duration(days: 1)));
      case PeriodoRendicion.semana:
        return (inicioSemana(ahora), ahora.add(const Duration(minutes: 1)));
      case PeriodoRendicion.mes:
        return (inicioMes(ahora), ahora.add(const Duration(minutes: 1)));
      case PeriodoRendicion.personalizado:
        final d = _desde ?? inicioHoy(ahora).subtract(const Duration(days: 7));
        final h = _hasta ?? ahora;
        return (d, h.add(const Duration(days: 1)));
    }
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final (desde, hasta) = _rango();
      final data = await rendicionRepo.calcular(
        desde: desde,
        hasta: hasta,
        motorizadoId: _motorizadoId,
      );
      if (!mounted) return;
      setState(() {
        _rendicion = data;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _elegirFechas() async {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _desde ?? DateTime.now().subtract(const Duration(days: 7)),
        end: _hasta ?? DateTime.now(),
      ),
    );
    if (rango == null) return;
    setState(() {
      _periodo = PeriodoRendicion.personalizado;
      _desde = rango.start;
      _hasta = rango.end;
    });
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final r = _rendicion;
    final nombreMotorizado = _motorizados
        .where((m) => m['id'] == _motorizadoId)
        .map((m) => m['nombre'] as String? ?? '')
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rendición'),
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
          // ---- Filtros ----
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in PeriodoRendicion.values)
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
                              if (p == PeriodoRendicion.personalizado) {
                                _elegirFechas();
                              } else {
                                _cargar();
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _motorizadoId,
                  decoration: const InputDecoration(
                    labelText: 'Motorizado',
                    isDense: true,
                    prefixIcon: Icon(Icons.delivery_dining_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Toda la empresa'),
                    ),
                    for (final m in _motorizados)
                      DropdownMenuItem<String?>(
                        value: m['id'] as String,
                        child: Text(m['nombre'] as String? ?? ''),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _motorizadoId = v);
                    _cargar();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      if (nombreMotorizado != null)
                        Text('Motorizado: $nombreMotorizado',
                            style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FilaValor('Pedidos realizados', '${r.pedidosRealizados}'),
                              FilaValor('Entregados', '${r.entregados}',
                                  color: AppTheme.success),
                              FilaValor('No entregados', '${r.noEntregados}',
                                  color: r.noEntregados > 0 ? AppTheme.danger : null),
                              FilaValor('Cancelados', '${r.cancelados}'),
                              FilaValor('Pendientes', '${r.pendientes}',
                                  color: AppTheme.warning),
                              const Divider(height: 22),
                              FilaValor('Total a cobrar', dinero(r.totalACobrar),
                                  destacado: true),
                              FilaValor('Cobrado', dinero(r.cobrado),
                                  color: AppTheme.success),
                              FilaValor('Pendiente', dinero(r.pendiente),
                                  color: r.pendiente > 0 ? AppTheme.danger : null),
                              const Divider(height: 22),
                              FilaValor('Yape', dinero(r.yape), color: AppTheme.info),
                              FilaValor('Efectivo', dinero(r.efectivo)),
                              if (r.otros > 0) FilaValor('Otros', dinero(r.otros)),
                              const Divider(height: 22),
                              FilaValor('Deudas generadas', dinero(r.deudasGeneradas),
                                  color: r.deudasGeneradas > 0 ? AppTheme.danger : null),
                              const Divider(height: 22),
                              FilaValor('Balones vacíos recibidos',
                                  '${r.balonesVaciosRecibidos}'),
                              FilaValor('Balones vacíos pendientes',
                                  '${r.balonesVaciosPendientes}',
                                  color: r.balonesVaciosPendientes > 0
                                      ? AppTheme.warning
                                      : null),
                              if (r.combustible > 0)
                                FilaValor('Combustible', dinero(r.combustible),
                                    color: AppTheme.danger),
                              const Divider(height: 22),
                              FilaValor('Gastos en efectivo', dinero(r.gastosEfectivo),
                                  color: r.gastosEfectivo > 0 ? AppTheme.danger : null),
                              FilaValor('Gastos en Yape', dinero(r.gastosYape),
                                  color: r.gastosYape > 0 ? AppTheme.danger : null),
                              if (r.gastosOtros > 0)
                                FilaValor('Gastos en otros', dinero(r.gastosOtros),
                                    color: AppTheme.danger),
                              FilaValor('Total gastos', dinero(r.gastosTotal),
                                  destacado: true,
                                  color: r.gastosTotal > 0 ? AppTheme.danger : null),
                            ],
                          ),
                        ),
                      ),
                      if (r.vacio)
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Text(
                            'No hay movimientos en este periodo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
