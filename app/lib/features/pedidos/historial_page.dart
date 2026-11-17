/// Historial del motorizado: los pedidos que ya atendió.
///
/// Solo los asignados/atendidos por ese motorizado. Agrupados por día y
/// filtrables (Hoy · Ayer · Todas). El estado que se pinta es el real de la
/// base: si el pedido está ENTREGADO nunca aparece como pendiente.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/actividad_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/state/bus.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';
import 'pedido_detalle_page.dart';

enum _Filtro { hoy, ayer, todas }

class HistorialPage extends ConsumerStatefulWidget {
  HistorialPage({super.key});

  @override
  ConsumerState<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends ConsumerState<HistorialPage> {
  List<Map<String, dynamic>> _pedidos = [];
  Map<String, String> _fotos = {};
  bool _cargando = true;
  String? _error;
  _Filtro _filtro = _Filtro.todas;

  /// Descarta respuestas viejas: si dos cargas se cruzan, solo pinta la última.
  int _peticion = 0;

  @override
  void initState() {
    super.initState();
    SyncBus.pedidos.addListener(_onBus);
    SyncBus.dinero.addListener(_onBus);
    SyncBus.movimientos.addListener(_onBus);
    _cargar();
  }

  @override
  void dispose() {
    SyncBus.pedidos.removeListener(_onBus);
    SyncBus.dinero.removeListener(_onBus);
    SyncBus.movimientos.removeListener(_onBus);
    super.dispose();
  }

  void _onBus() {
    if (mounted) _cargar();
  }

  Future<void> _cargar() async {
    final auth = ref.read(authProvider);
    final miPeticion = ++_peticion;
    try {
      final data = await pedidosRepo.listar(
        repartidorId: auth.esAdmin ? null : auth.usuarioId,
        estados: const ['ENTREGADO', 'NO_ENTREGADO', 'CANCELADO'],
        limite: 300,
      );
      final ids = data.map((p) => p['id'] as String? ?? '').where((e) => e.isNotEmpty).toList();
      final fotos = await actividadRepo.comprobantesDePedidos(ids);
      if (!mounted || miPeticion != _peticion) return;
      setState(() {
        _pedidos = data;
        _fotos = fotos;
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || miPeticion != _peticion) return;
      setState(() {
        _cargando = false;
        _error = traducirError(e, contexto: 'No pudimos cargar el historial').mensaje;
      });
    }
  }

  Future<void> _abrir(Map<String, dynamic> pedido) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PedidoDetallePage(pedido: pedido)),
    );
    if (cambio == true) _cargar();
  }

  List<Map<String, dynamic>> get _filtrados {
    if (_filtro == _Filtro.todas) return _pedidos;
    final ahora = DateTime.now();
    final hoy = inicioHoy(ahora);
    final desde = _filtro == _Filtro.hoy ? hoy : hoy.subtract(Duration(days: 1));
    final hasta = _filtro == _Filtro.hoy ? hoy.add(Duration(days: 1)) : hoy;
    return _pedidos.where((p) {
      final f = parseFecha(p['fecha']);
      return f != null && !f.isBefore(desde) && f.isBefore(hasta);
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> _porDia(List<Map<String, dynamic>> lista) {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final p in lista) {
      final fecha = parseFecha(p['fecha']);
      if (fecha == null) continue;
      final dia = fechaRelativa(fecha).split(' ').first;
      grupos.putIfAbsent(dia, () => []).add(p);
    }
    return grupos;
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    final grupos = _porDia(lista);
    return Scaffold(
      appBar: AppBar(title: Text('Historial de entregas')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<_Filtro>(
              segments: const [
                ButtonSegment(value: _Filtro.hoy, label: Text('Hoy')),
                ButtonSegment(value: _Filtro.ayer, label: Text('Ayer')),
                ButtonSegment(value: _Filtro.todas, label: Text('Todas')),
              ],
              selected: {_filtro},
              onSelectionChanged: (s) => setState(() => _filtro = s.first),
            ),
          ),
          Expanded(child: _cuerpo(grupos)),
        ],
      ),
    );
  }

  Widget _cuerpo(Map<String, List<Map<String, dynamic>>> grupos) {
    if (_cargando) {
      return Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: AppTheme.danger),
              SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              SizedBox(height: 12),
              FilledButton(onPressed: _cargar, child: Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (grupos.isEmpty) {
      return EstadoVacio(
        icono: Icons.history,
        titulo: 'Sin entregas en este periodo',
        mensaje: 'Aquí verás el historial real de tus entregas.',
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final entrada in grupos.entries) ...[
            Padding(
              padding: EdgeInsets.only(top: 6, bottom: 8),
              child: Text(entrada.key, style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final p in entrada.value)
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: _FilaHistorial(
                  pedido: p,
                  fotoUrl: _fotos[p['id']],
                  onTap: () => _abrir(p),
                ),
              ),
            SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _FilaHistorial extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final String? fotoUrl;
  final VoidCallback onTap;

  const _FilaHistorial({required this.pedido, required this.onTap, this.fotoUrl});

  @override
  Widget build(BuildContext context) {
    final cliente = pedido['clientes'] as Map<String, dynamic>?;
    final estado = pedido['estado'] as String? ?? '';
    final forma = pedido['forma_pago'] as String?;
    final total = (pedido['total'] as num? ?? 0).toDouble();
    final fecha = parseFecha(pedido['fecha']);
    final hora = fecha == null
        ? ''
        : '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              if (fotoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    fotoUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.image_not_supported_outlined,
                      size: 28,
                      color: AppColors.textoMuted,
                    ),
                  ),
                )
              else
                Icon(
                  estado == 'ENTREGADO' ? Icons.check_circle : Icons.cancel_outlined,
                  color: estado == 'ENTREGADO' ? AppTheme.success : AppTheme.danger,
                ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cliente?['nombre'] as String? ?? 'Cliente',
                            style: TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        EstadoBadge(estado, compacto: true),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      [
                        hora.isEmpty ? '#${pedido['numero']}' : '$hora · #${pedido['numero']}',
                        if (forma != null) metodoPago(forma),
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: AppColors.textoSecundario),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Text(
                dinero(total),
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}