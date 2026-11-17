/// Rendición de cuentas por motorizado.
///
/// El admin elige el periodo y el motorizado, y ve los números reales:
/// pedidos, cobros, deudas y balones.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/fondo_vuelto_repo.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/state/bus.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

/// Periodos disponibles.
enum PeriodoRendicion {
  hoy('Hoy'),
  ayer('Ayer'),
  semana('Esta semana'),
  mes('Este mes'),
  personalizado('Personalizado');

  PeriodoRendicion(this.label);

  final String label;
}

class RendicionPage extends ConsumerStatefulWidget {
  RendicionPage({super.key});

  @override
  ConsumerState<RendicionPage> createState() => _RendicionPageState();
}

class _RendicionPageState extends ConsumerState<RendicionPage> {
  PeriodoRendicion _periodo = PeriodoRendicion.hoy;
  DateTime? _desde;
  DateTime? _hasta;
  List<Map<String, dynamic>> _motorizados = [];
  String? _motorizadoId;
  Rendicion _rendicion = Rendicion();
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    SyncBus.dinero.addListener(_onBus);
    SyncBus.movimientos.addListener(_onBus);
    SyncBus.rendiciones.addListener(_onBus);
    _cargarMotorizados();
    _cargar();
  }

  @override
  void dispose() {
    SyncBus.dinero.removeListener(_onBus);
    SyncBus.movimientos.removeListener(_onBus);
    SyncBus.rendiciones.removeListener(_onBus);
    super.dispose();
  }

  void _onBus() {
    if (mounted) _cargar(silencioso: true);
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
        return (inicioHoy(ahora), ahora.add(Duration(minutes: 1)));
      case PeriodoRendicion.ayer:
        final ayer = inicioHoy(ahora).subtract(Duration(days: 1));
        return (ayer, ayer.add(Duration(days: 1)));
      case PeriodoRendicion.semana:
        return (inicioSemana(ahora), ahora.add(Duration(minutes: 1)));
      case PeriodoRendicion.mes:
        return (inicioMes(ahora), ahora.add(Duration(minutes: 1)));
      case PeriodoRendicion.personalizado:
        final d = _desde ?? inicioHoy(ahora).subtract(Duration(days: 7));
        final h = _hasta ?? ahora;
        return (d, h.add(Duration(days: 1)));
    }
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _cargando = true);
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            traducirError(e, contexto: 'No pudimos calcular la rendición')
                .mensaje,
          ),
        ),
      );
    }
  }

  Future<void> _elegirFechas() async {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _desde ?? DateTime.now().subtract(Duration(days: 7)),
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

  /// El administrador entrega dinero de vuelto al motorizado al inicio de la
  /// jornada. No es venta ni ingreso: es un fondo que debe volver.
  Future<void> _entregarFondo() async {
    final auth = ref.read(authProvider);
    if (_motorizados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No hay motorizados registrados.')),
      );
      return;
    }
    String? moto = _motorizadoId ?? _motorizados.first['id'] as String;
    String medio = 'EFECTIVO';
    final montoCtrl = TextEditingController();
    final obsCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Entregar fondo de vuelto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: moto,
                  decoration: InputDecoration(
                    labelText: 'Motorizado',
                    prefixIcon: Icon(Icons.delivery_dining_outlined),
                  ),
                  items: [
                    for (final m in _motorizados)
                      DropdownMenuItem<String>(
                        value: m['id'] as String,
                        child: Text(m['nombre'] as String? ?? ''),
                      ),
                  ],
                  onChanged: (v) => setDlg(() => moto = v),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: montoCtrl,
                  keyboardType:
                      TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Monto entregado',
                    prefixText: 'S/ ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.swap_horiz, size: 18, color: AppColors.textoMuted),
                    SizedBox(width: 8),
                    Text('Cómo se entrega',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      avatar: Icon(Icons.payments_outlined, size: 17),
                      label: Text('Efectivo'),
                      selected: medio == 'EFECTIVO',
                      selectedColor: AppTheme.success.withValues(alpha: 0.12),
                      onSelected: (_) => setDlg(() => medio = 'EFECTIVO'),
                    ),
                    ChoiceChip(
                      avatar: Icon(Icons.account_balance_wallet_outlined,
                          size: 17),
                      label: Text('Yape'),
                      selected: medio == 'YAPE',
                      selectedColor: AppTheme.info.withValues(alpha: 0.12),
                      onSelected: (_) => setDlg(() => medio = 'YAPE'),
                    ),
                  ],
                ),
                if (medio == 'YAPE')
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'El vuelto por Yape no se cuenta como efectivo físico '
                      'en la rendición.',
                      style: TextStyle(fontSize: 12, color: AppTheme.info),
                    ),
                  ),
                SizedBox(height: 12),
                TextField(
                  controller: obsCtrl,
                  decoration: InputDecoration(
                    labelText: 'Observación (opcional)',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Entregar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || moto == null || !mounted) return;

    final monto = double.tryParse(montoCtrl.text.replaceAll(',', '.')) ?? 0;
    if (monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Escribe un monto mayor a cero.')),
      );
      return;
    }
    try {
      await fondoVueltoRepo.entregar(
        empresaId: auth.empresaId!,
        motorizadoId: moto!,
        entregadoPor: auth.usuarioId!,
        monto: monto,
        medioPago: medio,
        observaciones: obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fondo de vuelto registrado. Ya aparece en la rendición.'),
        ),
      );
      _cargar(silencioso: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(traducirError(e, contexto: 'No pudimos registrar el fondo').mensaje),
        ),
      );
    }
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
        title: Text('Rendición'),
        actions: [
          TextButton.icon(
            onPressed: _entregarFondo,
            icon: Icon(Icons.money_outlined),
            label: Text('Fondo'),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // ---- Filtros ----
          Container(
            color: AppColors.superficie,
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in PeriodoRendicion.values)
                        Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(p.label),
                            selected: _periodo == p,
                            selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                              color: _periodo == p ? AppTheme.primary : AppColors.textoPrincipal,
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
                SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _motorizadoId,
                  decoration: InputDecoration(
                    labelText: 'Motorizado',
                    isDense: true,
                    prefixIcon: Icon(Icons.delivery_dining_outlined),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
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
          Divider(height: 1),
          Expanded(
            child: _cargando
                ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : RefreshIndicator(
                    onRefresh: () => _cargar(silencioso: true),
                    child: ListView(
                      physics: AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                      if (nombreMotorizado != null)
                        Text('Motorizado: $nombreMotorizado',
                            style: Theme.of(context).textTheme.titleMedium),
                      SizedBox(height: 10),
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FilaValor('Pedidos realizados', '${r.pedidosRealizados}'),
                              FilaValor('Registrados por motorizado',
                                  '${r.pedidosManuales}'),
                              FilaValor('Entregados', '${r.entregados}',
                                  color: AppTheme.success),
                              FilaValor('No entregados', '${r.noEntregados}',
                                  color: r.noEntregados > 0 ? AppTheme.danger : null),
                              FilaValor('Cancelados', '${r.cancelados}'),
                              FilaValor('Pendientes', '${r.pendientes}',
                                  color: AppTheme.warning),
                              Divider(height: 22),
                              FilaValor('Total a cobrar', dinero(r.totalACobrar),
                                  destacado: true),
                              FilaValor('Cobrado', dinero(r.cobrado),
                                  color: AppTheme.success),
                              FilaValor('Pendiente', dinero(r.pendiente),
                                  color: r.pendiente > 0 ? AppTheme.danger : null),
                              Divider(height: 22),
                              FilaValor('Efectivo cobrado', dinero(r.efectivo)),
                              FilaValor('Yape cobrado', dinero(r.yape),
                                  color: AppTheme.info),
                              FilaValor('Total recibido', dinero(r.totalRecibido),
                                  destacado: true),
                              Divider(height: 22),
                              FilaValor('Fondo en efectivo',
                                  dinero(r.fondoInicial), color: AppTheme.info),
                              if (r.fondoYape > 0)
                                FilaValor('Fondo por Yape (no es efectivo)',
                                    dinero(r.fondoYape),
                                    color: AppTheme.info),
                              FilaValor('Total gastos', dinero(r.totalGastos),
                                  color: r.totalGastos > 0 ? AppTheme.danger : null),
                              Divider(height: 22),
                              FilaValor('DINERO ESPERADO', dinero(r.dineroEsperado),
                                  destacado: true, color: AppTheme.success),
                              FilaValor('Efectivo físico esperado',
                                  dinero(r.efectivoEsperado)),
                              if (r.hayDeclaracion) ...[
                                FilaValor('Efectivo declarado',
                                    dinero(r.efectivoDeclarado)),
                                FilaValor(
                                  'Diferencia',
                                  '${r.diferencia >= 0 ? '+' : '-'}${dinero(r.diferencia.abs())}',
                                  color: r.tieneDiferencia
                                      ? AppTheme.danger
                                      : AppTheme.success,
                                  destacado: true,
                                ),
                              ],
                              Divider(height: 22),
                              FilaValor('Deudas generadas', dinero(r.deudasGeneradas),
                                  color: r.deudasGeneradas > 0 ? AppTheme.danger : null),
                              Divider(height: 22),
                              FilaValor('Balones entregados', '${r.balonesEntregados}'),
                              FilaValor('Balones devueltos', '${r.balonesDevueltos}',
                                  color: AppTheme.success),
                              FilaValor('Balones vacíos pendientes',
                                  '${r.balonesVaciosPendientes}',
                                  color: r.balonesVaciosPendientes > 0
                                      ? AppTheme.warning
                                      : null),
                              if (r.combustible > 0)
                                FilaValor('Combustible', dinero(r.combustible),
                                    color: AppTheme.danger),
                              Divider(height: 22),
                              for (final e in r.gastosPorCategoria.entries)
                                FilaValor(e.key, dinero(e.value),
                                    color: AppTheme.warning),
                              FilaValor('Total gastos', dinero(r.gastosTotal),
                                  destacado: true,
                                  color: r.gastosTotal > 0 ? AppTheme.danger : null),
                              if (r.incidencias > 0)
                                FilaValor(
                                  'Fallas (${r.incidencias})',
                                  dinero(r.incidenciasTotal),
                                  color: AppTheme.danger,
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (r.vacio)
                        Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Text(
                            'No hay movimientos en este periodo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textoSecundario),
                          ),
                        ),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }
}