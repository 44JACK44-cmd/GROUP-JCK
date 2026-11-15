/// Actividad de los motorizados (vista del recepcionista/admin).
///
/// Muestra, por motorizado, el resumen del día y la lista de movimientos
/// (pedidos entregados y gastos) en orden cronológico. Se actualiza en tiempo
/// real cuando un motorizado registra algo.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class MotorizadosActividadPage extends ConsumerStatefulWidget {
  const MotorizadosActividadPage({super.key});

  @override
  ConsumerState<MotorizadosActividadPage> createState() =>
      _MotorizadosActividadPageState();
}

class _MotorizadosActividadPageState
    extends ConsumerState<MotorizadosActividadPage> {
  List<Map<String, dynamic>> _motorizados = [];
  Map<String, Rendicion> _resumen = {};
  bool _cargando = true;
  RealtimeChannel? _canal;

  @override
  void initState() {
    super.initState();
    _cargar();
    _escucharRealtime();
  }

  @override
  void dispose() {
    _canal?.unsubscribe();
    super.dispose();
  }

  void _escucharRealtime() {
    try {
      _canal = sb
          .channel('moto-actividad')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'pedidos',
            callback: (_) {
              if (mounted) _cargar();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'gastos',
            callback: (_) {
              if (mounted) _cargar();
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _cargar() async {
    try {
      final motos = await motorizadosRepo.listar();
      final inicio = inicioHoy();
      final fin = DateTime.now().add(const Duration(minutes: 1));
      final resumenes = <String, Rendicion>{};
      await Future.wait(motos.map((m) async {
        final r = await rendicionRepo.calcular(
          desde: inicio,
          hasta: fin,
          motorizadoId: m['id'] as String,
        );
        resumenes[m['id'] as String] = r;
      }));
      if (!mounted) return;
      setState(() {
        _motorizados = motos;
        _resumen = resumenes;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _configurarDias(Map<String, dynamic> moto) async {
    final id = moto['id'] as String;
    final nombre = moto['nombre'] as String? ?? '';
    final dias = await motorizadosRepo.diasTrabajo(id);
    final seleccion = <int>{...(dias ?? [1, 2, 3, 4, 5, 6, 7])};
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: Text('Días de trabajo — $nombre'),
            content: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 1; i <= 7; i++)
                  FilterChip(
                    label: Text(_nombreDia(i)),
                    selected: seleccion.contains(i),
                    onSelected: (v) => setSt(() {
                      if (v) {
                        seleccion.add(i);
                      } else {
                        seleccion.remove(i);
                      }
                    }),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    await motorizadosRepo.guardarDiasTrabajo(
      id,
      seleccion.isEmpty ? null : (seleccion.toList()..sort()),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Días de trabajo de $nombre actualizados.')),
      );
    }
  }

  String _nombreDia(int d) => const ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'][d - 1];

  Future<void> _abrirDetalle(Map<String, dynamic> moto) async {
    final id = moto['id'] as String;
    final nombre = moto['nombre'] as String? ?? '';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ActividadMotorizadoPage(
          motorizadoId: id,
          nombre: nombre,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Motorizados')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_motorizados.isEmpty)
                    const EstadoVacio(
                      icono: Icons.delivery_dining_outlined,
                      titulo: 'No hay motorizados registrados',
                    )
                  else
                    for (final m in _motorizados)
                      _TarjetaMotorizado(
                        nombre: m['nombre'] as String? ?? '',
                        activo: m['activo'] as bool? ?? true,
                        resumen: _resumen[m['id'] as String] ?? const Rendicion(),
                        onTap: () => _abrirDetalle(m),
                        onConfigurarDias: () => _configurarDias(m),
                      ),
                ],
              ),
            ),
    );
  }
}

class _TarjetaMotorizado extends StatelessWidget {
  final String nombre;
  final bool activo;
  final Rendicion resumen;
  final VoidCallback onTap;
  final VoidCallback onConfigurarDias;

  const _TarjetaMotorizado({
    required this.nombre,
    required this.activo,
    required this.resumen,
    required this.onTap,
    required this.onConfigurarDias,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                    child: Text(
                      nombre.isEmpty ? '?' : nombre[0].toUpperCase(),
                      style: const TextStyle(color: AppTheme.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          activo ? 'Activo' : 'Inactivo',
                          style: TextStyle(
                            fontSize: 12,
                            color: activo ? AppTheme.success : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Días de trabajo',
                    onPressed: onConfigurarDias,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black45),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Mini('Pedidos', '${resumen.pedidosRealizados}'),
                  _Mini('Ventas', dinero(resumen.totalACobrar)),
                  _Mini('Efectivo', dinero(resumen.efectivo)),
                  _Mini('Yape', dinero(resumen.yape)),
                ],
              ),
              if (resumen.gastosTotal > 0 || resumen.pendiente > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (resumen.gastosTotal > 0)
                      _Mini('Gastos', dinero(resumen.gastosTotal), color: AppTheme.warning),
                    if (resumen.pendiente > 0)
                      _Mini('Deudas', dinero(resumen.pendiente), color: AppTheme.danger),
                    if (resumen.balonesVaciosPendientes > 0)
                      _Mini('Balones pend.', '${resumen.balonesVaciosPendientes}',
                          color: AppTheme.warning),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final Color? color;

  const _Mini(this.etiqueta, this.valor, {this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          Text(
            valor,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Detalle de actividad de un motorizado (pedidos + gastos de hoy).
class _ActividadMotorizadoPage extends StatefulWidget {
  final String motorizadoId;
  final String nombre;

  const _ActividadMotorizadoPage({
    required this.motorizadoId,
    required this.nombre,
  });

  @override
  State<_ActividadMotorizadoPage> createState() => _ActividadMotorizadoPageState();
}

class _ActividadMotorizadoPageState extends State<_ActividadMotorizadoPage> {
  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _gastos = [];
  Map<String, String> _comprobantes = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final inicio = inicioHoy();
      final fin = DateTime.now().add(const Duration(minutes: 1));
      final pedidos = await pedidosRepo.listar(
        repartidorId: widget.motorizadoId,
        desde: inicio,
        hasta: fin,
        limite: 200,
        masAntigosPrimero: false,
      );
      // Gastos del motorizado: consulta directa (no hay repositorio dedicado).
      List<Map<String, dynamic>> gastos = [];
      try {
        final data = await sb
            .from('gastos')
            .select('id, tipo, descripcion, monto, medio_pago, fecha, usuario_id')
            .eq('usuario_id', widget.motorizadoId)
            .gte('fecha', inicio.toIso8601String())
            .lte('fecha', fin.toIso8601String())
            .order('fecha', ascending: false)
            .limit(100);
        gastos = List<Map<String, dynamic>>.from(data);
      } catch (_) {}
      // Comprobantes Yape por pedido.
      final comp = <String, String>{};
      try {
        if (pedidos.isNotEmpty) {
          final ids = pedidos.map((p) => p['id']).toList();
          final pagos = await sb
              .from('pagos')
              .select('pedido_id, comprobante_url')
              .inFilter('pedido_id', ids);
          for (final pg in (pagos as List)) {
            final pid = pg['pedido_id'] as String?;
            final url = pg['comprobante_url'] as String?;
            if (pid != null && url != null && url.isNotEmpty) {
              comp[pid] = url;
            }
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _pedidos = pedidos;
        _gastos = gastos;
        _comprobantes = comp;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mezclar pedidos y gastos por fecha.
    final items = <_ItemActividad>[];
    for (final p in _pedidos) {
      items.add(_ItemActividad(
        fecha: parseFecha(p['fecha']) ?? DateTime.now(),
        titulo: 'Pedido #${p['numero'] ?? ''}',
        subtitulo: '${(p['clientes'] as Map?)?['nombre'] ?? ''} · ${dinero((p['total'] as num? ?? 0).toDouble())}',
        detalle: p['forma_pago'] as String? ?? '',
        esGasto: false,
        estado: p['estado'] as String? ?? '',
        pedidoId: p['id'] as String?,
      ));
    }
    for (final g in _gastos) {
      items.add(_ItemActividad(
        fecha: parseFecha(g['fecha']) ?? DateTime.now(),
        titulo: 'Gasto: ${g['tipo'] ?? g['descripcion'] ?? 'Gasto'}',
        subtitulo: dinero((g['monto'] as num? ?? 0).toDouble()),
        detalle: g['medio_pago'] as String? ?? '',
        esGasto: true,
        estado: '',
      ));
    }
    items.sort((a, b) => b.fecha.compareTo(a.fecha));

    return Scaffold(
      appBar: AppBar(title: Text(widget.nombre)),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: EstadoVacio(
                        icono: Icons.history_outlined,
                        titulo: 'Sin actividad hoy',
                      ),
                    )
                  else
                    for (final it in items)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            it.esGasto ? Icons.money_off_outlined : Icons.receipt_long_outlined,
                            color: it.esGasto ? AppTheme.warning : AppTheme.primary,
                          ),
                          title: Text(it.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${it.subtitulo}\n${_hora(it.fecha)}${it.detalle.isNotEmpty ? ' · ${it.detalle}' : ''}'),
                          isThreeLine: true,
                          trailing: it.esGasto
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_comprobantes.containsKey(it.pedidoId))
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.network(
                                            _comprobantes[it.pedidoId]!,
                                            width: 36,
                                            height: 36,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    EstadoBadge(it.estado, compacto: true),
                                  ],
                                ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }

  String _hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _ItemActividad {
  final DateTime fecha;
  final String titulo;
  final String subtitulo;
  final String detalle;
  final bool esGasto;
  final String estado;
  final String? pedidoId;

  _ItemActividad({
    required this.fecha,
    required this.titulo,
    required this.subtitulo,
    required this.detalle,
    required this.esGasto,
    required this.estado,
    this.pedidoId,
  });
}
