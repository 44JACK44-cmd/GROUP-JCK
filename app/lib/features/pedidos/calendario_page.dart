/// Calendario de pedidos y motorizados.
///
/// Vista simple: un mes con contadores por día. Al tocar un día se ven los
/// pedidos de ese día y los motorizados que trabajan.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/domain/formato.dart';
import '../../core/domain/resumen_pedido.dart';
import '../auth/auth_controller.dart';

const _diasSemana = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const _meses = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

class CalendarioPage extends ConsumerStatefulWidget {
  CalendarioPage({super.key});

  @override
  ConsumerState<CalendarioPage> createState() => _CalendarioPageState();
}

class _CalendarioPageState extends ConsumerState<CalendarioPage> {
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  Map<int, List<Map<String, dynamic>>> _pedidosPorDia = {};
  List<Map<String, dynamic>> _motorizados = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final inicioMes = DateTime(_mes.year, _mes.month, 1);
      final finMes = DateTime(_mes.year, _mes.month + 1, 0, 23, 59, 59);
      final auth = ref.read(authProvider);
      final repartidorId = auth.esMotorizado ? auth.usuarioId : null;
      final pedidos = await pedidosRepo.listar(
        repartidorId: repartidorId,
        desde: inicioMes,
        hasta: finMes,
        limite: 500,
        masAntigosPrimero: true,
      );
      final motos = await motorizadosRepo.listar();
      final mapa = <int, List<Map<String, dynamic>>>{};
      for (final p in pedidos) {
        final f = parseFecha(p['fecha']);
        if (f == null) continue;
        mapa.putIfAbsent(f.day, () => []).add(p);
      }
      if (!mounted) return;
      setState(() {
        _pedidosPorDia = mapa;
        _motorizados = motos;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  int _primerDiaOffset() {
    // DateTime.weekday: 1=Mon..7=Sun. Grid starts Monday.
    final primer = DateTime(_mes.year, _mes.month, 1);
    return primer.weekday - 1; // 0..6
  }

  int _diasEnMes() => DateTime(_mes.year, _mes.month + 1, 0).day;

  Future<void> _abrirDia(int dia) async {
    final pedidos = _pedidosPorDia[dia] ?? const [];
    final fecha = DateTime(_mes.year, _mes.month, dia);
    final diaSemana = fecha.weekday;
    final activos = <Map<String, dynamic>>[];
    for (final m in _motorizados) {
      final dias = await motorizadosRepo.diasTrabajo(m['id'] as String);
      if (motorizadosRepo.trabajaHoy(dias, diaSemana)) {
        activos.add(m);
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              '${dia} de ${_meses[_mes.month - 1]} ${_mes.year}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              '${pedidos.length} pedido(s) · ${activos.length} motorizado(s) activo(s)',
              style: TextStyle(color: AppColors.textoSecundario),
            ),
            SizedBox(height: 12),
            if (activos.isNotEmpty) ...[
              Text('Motorizados activos', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in activos)
                    Chip(
                      avatar: Icon(Icons.delivery_dining_outlined, size: 16),
                      label: Text(m['nombre'] as String? ?? ''),
                    ),
                ],
              ),
              SizedBox(height: 12),
            ],
            Text('Pedidos', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            if (pedidos.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Sin pedidos este día.', style: TextStyle(color: AppColors.textoSecundario)),
              )
            else
              for (final p in pedidos)
                Card(
                  margin: EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text((p['clientes'] as Map?)?['nombre'] as String? ?? 'Cliente'),
                    subtitle: Text(
                      '${resumenProductos(p)}\n'
                      '${_hora(parseFecha(p['fecha']))} · ${p['forma_pago'] ?? ''}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      dinero((p['total'] as num? ?? 0).toDouble()),
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _hora(DateTime? d) {
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final offset = _primerDiaOffset();
    final totalDias = _diasEnMes();
    final celdas = offset + totalDias;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_meses[_mes.month - 1]} ${_mes.year}'),
        actions: [
          IconButton(
            tooltip: 'Hoy',
            onPressed: () {
              setState(() => _mes = DateTime(hoy.year, hoy.month));
              _cargar();
            },
            icon: Icon(Icons.today),
          ),
        ],
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() => _mes = DateTime(_mes.year, _mes.month - 1));
                          _cargar();
                        },
                        icon: Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${_meses[_mes.month - 1]} ${_mes.year}',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _mes = DateTime(_mes.year, _mes.month + 1));
                          _cargar();
                        },
                        icon: Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      for (final d in _diasSemana)
                        Expanded(
                          child: Center(
                            child: Text(d, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textoMuted)),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 4),
                Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: celdas,
                    itemBuilder: (context, i) {
                      if (i < offset) return SizedBox.shrink();
                      final dia = i - offset + 1;
                      if (dia > totalDias) return SizedBox.shrink();
                      final pedidos = _pedidosPorDia[dia] ?? const [];
                      final esHoy = hoy.year == _mes.year &&
                          hoy.month == _mes.month &&
                          hoy.day == dia;
                      return InkWell(
                        onTap: () => _abrirDia(dia),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          margin: EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: esHoy ? AppTheme.primary.withValues(alpha: 0.12) : null,
                            borderRadius: BorderRadius.circular(8),
                            border: esHoy
                                ? Border.all(color: AppTheme.primary, width: 1.4)
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$dia',
                                style: TextStyle(
                                  fontWeight: esHoy ? FontWeight.bold : FontWeight.w500,
                                  color: esHoy ? AppTheme.primary : AppColors.textoPrincipal,
                                ),
                              ),
                              if (pedidos.isNotEmpty)
                                Container(
                                  margin: EdgeInsets.only(top: 2),
                                  padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${pedidos.length}',
                                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}