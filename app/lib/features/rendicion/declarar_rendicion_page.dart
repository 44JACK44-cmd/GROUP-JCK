/// Declaración de rendición por el motorizado.
///
/// El motorizado declara cuánto dinero entrega al final de la jornada.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../app/theme.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/data/rendiciones_repo.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/diseno.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class DeclararRendicionPage extends ConsumerStatefulWidget {
  DeclararRendicionPage({super.key});

  @override
  ConsumerState<DeclararRendicionPage> createState() => _DeclararRendicionPageState();
}

class _DeclararRendicionPageState extends ConsumerState<DeclararRendicionPage> {
  final _efectivoCtrl = TextEditingController();
  final _yapeCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  bool _guardando = false;
  bool _cargando = true;
  Rendicion? _rendicionCalculada;

  @override
  void initState() {
    super.initState();
    _cargarRendicion();
  }

  @override
  void dispose() {
    _efectivoCtrl.dispose();
    _yapeCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarRendicion() async {
    final uid = ref.read(authProvider).usuarioId;
    if (uid == null) return;
    try {
      final inicio = inicioHoy();
      final fin = DateTime.now().add(Duration(minutes: 1));
      final res = await Future.wait([
        rendicionRepo.calcular(desde: inicio, hasta: fin, motorizadoId: uid),
        rendicionesRepo.listar(
          motorizadoId: uid,
          desde: inicio,
          hasta: fin.add(const Duration(days: 1)),
        ),
      ]);
      if (!mounted) return;
      final data = res[0] as Rendicion;
      final yaDeclarado = (res[1] as List).isEmpty
          ? null
          : (res[1] as List).first as Map<String, dynamic>;
      setState(() {
        _rendicionCalculada = data;
        _cargando = false;
        // Si ya existe una rendición para hoy se carga, no se crea otra.
        _efectivoCtrl.text = yaDeclarado != null
            ? (yaDeclarado['efectivo_declarado'] as num? ?? 0).toStringAsFixed(2)
            : data.efectivoEsperado.toStringAsFixed(2);
        _yapeCtrl.text = yaDeclarado != null
            ? (yaDeclarado['yape_declarado'] as num? ?? 0).toStringAsFixed(2)
            : data.yape.toStringAsFixed(2);
        if (yaDeclarado != null) {
          _observacionesCtrl.text = yaDeclarado['observaciones'] as String? ?? '';
        }
      });
    } catch (e) {
      debugPrint('[RENDICION] Error al cargar: $e');
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _declarar() async {
    final efectivo = double.tryParse(_efectivoCtrl.text) ?? 0;
    final yape = double.tryParse(_yapeCtrl.text) ?? 0;

    if (efectivo < 0 || yape < 0) {
      _error('Los montos no pueden ser negativos.');
      return;
    }

    setState(() => _guardando = true);
    final auth = ref.read(authProvider);
    try {
      await rendicionesRepo.declarar(
        empresaId: auth.empresaId!,
        motorizadoId: auth.usuarioId!,
        efectivoDeclarado: efectivo,
        yapeDeclarado: yape,
        fondoInicial: _rendicionCalculada?.fondoInicial ?? 0,
        efectivoEsperado: _rendicionCalculada?.efectivoEsperado,
        observaciones: _observacionesCtrl.text.trim().isEmpty ? null : _observacionesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rendición declarada. El administrador la revisará.')),
      );
    } catch (e) {
      debugPrint('[RENDICION] Error al declarar: $e');
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is Exception && e.toString().contains('aprobada')
                ? 'Esta rendición ya fue aprobada y no se puede modificar.'
                : 'No se pudo registrar la rendición. Revisa los datos e inténtalo nuevamente.',
          ),
        ),
      );
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _diferenciaWidget(Rendicion r) {
    final declarado = double.tryParse(_efectivoCtrl.text.replaceAll(',', '.')) ?? 0;
    final diferencia = declarado - r.efectivoEsperado;
    final color = diferencia.abs() <= 0.009 ? AppTheme.success : AppTheme.danger;
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilaValor('Esperado', dinero(r.efectivoEsperado)),
          FilaValor('Declarado', dinero(declarado)),
          FilaValor(
            'Diferencia',
            '${diferencia >= 0 ? '+' : '-'}${dinero(diferencia.abs())}',
            color: color,
            destacado: true,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _rendicionCalculada;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi rendición')),
      body: _cargando
          ? const LoadingState()
          : ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (r != null) ...[
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resumen del día', style: Theme.of(context).textTheme.titleMedium),
                    SizedBox(height: 10),
                    FilaValor('Pedidos entregados', '${r.entregados}'),
                    FilaValor('Registrados por mí', '${r.pedidosManuales}'),
                    FilaValor('Ventas', dinero(r.totalACobrar)),
                    FilaValor('Efectivo cobrado', dinero(r.efectivo)),
                    FilaValor('Yape cobrado', dinero(r.yape), color: AppTheme.info),
                    FilaValor('Total recibido', dinero(r.totalRecibido),
                        destacado: true),
                    FilaValor('Deuda pendiente', dinero(r.pendiente),
                        color: AppTheme.warning),
                    Divider(height: 18),
                    for (final e in r.gastosPorCategoria.entries)
                      FilaValor(e.key, dinero(e.value), color: AppTheme.warning),
                    FilaValor('Total gastos', dinero(r.totalGastos),
                        color: AppTheme.danger),
                    if (r.incidencias > 0)
                      FilaValor('Fallas (${r.incidencias})',
                          dinero(r.incidenciasTotal), color: AppTheme.danger),
                    FilaValor('Fondo en efectivo', dinero(r.fondoInicial),
                        color: AppTheme.info),
                    if (r.fondoYape > 0)
                      FilaValor('Fondo por Yape (no es efectivo)',
                          dinero(r.fondoYape), color: AppTheme.info),
                    Divider(height: 18),
                    FilaValor('DINERO ESPERADO', dinero(r.dineroEsperado),
                        destacado: true, color: AppTheme.success),
                    FilaValor('Efectivo físico esperado',
                        dinero(r.efectivoEsperado)),
                    FilaValor('Balones entregados', '${r.balonesEntregados}'),
                    FilaValor('Balones devueltos', '${r.balonesDevueltos}'),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
          ],
          Text('¿Cuánto dinero entregas?', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          TextFormField(
            controller: _efectivoCtrl,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Efectivo entregado',
              prefixText: 'S/ ',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (r != null) ...[
            SizedBox(height: 8),
            _diferenciaWidget(r),
          ],
          SizedBox(height: 12),
          TextFormField(
            controller: _yapeCtrl,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Yape declarado',
              prefixText: 'S/ ',
              prefixIcon: Icon(Icons.phone_android_outlined),
            ),
          ),
          SizedBox(height: 12),
          TextFormField(
            controller: _observacionesCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Observaciones (opcional)',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _guardando ? null : _declarar,
            icon: Icon(Icons.check_circle_outline),
            label: Text(_guardando ? 'Declarando…' : 'Declarar rendición'),
            style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(52),
              backgroundColor: AppTheme.success,
            ),
          ),
        ],
      ),
    );
  }
}