/// Declaración de rendición por el motorizado.
///
/// El motorizado declara cuánto dinero entrega al final de la jornada.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../app/theme.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/data/rendiciones_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class DeclararRendicionPage extends ConsumerStatefulWidget {
  const DeclararRendicionPage({super.key});

  @override
  ConsumerState<DeclararRendicionPage> createState() => _DeclararRendicionPageState();
}

class _DeclararRendicionPageState extends ConsumerState<DeclararRendicionPage> {
  final _efectivoCtrl = TextEditingController();
  final _yapeCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  bool _guardando = false;
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
      final fin = DateTime.now().add(const Duration(minutes: 1));
      final data = await rendicionRepo.calcular(desde: inicio, hasta: fin, motorizadoId: uid);
      if (!mounted) return;
      setState(() {
        _rendicionCalculada = data;
        // Se precarga lo que DEBERÍA entregarse (con fondo y menos gastos),
        // no solo lo cobrado: el motorizado declara el dinero físico.
        _efectivoCtrl.text = data.efectivoEsperado.toStringAsFixed(2);
        _yapeCtrl.text = data.yape.toStringAsFixed(2);
      });
    } catch (_) {}
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
        const SnackBar(content: Text('Rendición declarada. El administrador la revisará.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos declarar la rendición').mensaje)),
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
      padding: const EdgeInsets.all(12),
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
      appBar: AppBar(title: const Text('Declarar rendición')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (r != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resumen del día', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    FilaValor('Pedidos entregados', '${r.entregados}'),
                    FilaValor('Registrados por mí', '${r.pedidosManuales}'),
                    FilaValor('Ventas', dinero(r.totalACobrar)),
                    FilaValor('Efectivo cobrado', dinero(r.efectivo)),
                    FilaValor('Yape (no va en efectivo)', dinero(r.yape),
                        color: AppTheme.info),
                    FilaValor('Deuda (no va en efectivo)', dinero(r.pendiente),
                        color: AppTheme.warning),
                    if (r.gastosTotal > 0)
                      FilaValor('Gastos', dinero(r.gastosTotal), color: AppTheme.danger),
                    if (r.incidencias > 0)
                      FilaValor('Fallas (${r.incidencias})',
                          dinero(r.incidenciasTotal), color: AppTheme.danger),
                    FilaValor('Fondo en efectivo', dinero(r.fondoInicial),
                        color: AppTheme.info),
                    if (r.fondoYape > 0)
                      FilaValor('Fondo por Yape (no es efectivo)',
                          dinero(r.fondoYape), color: AppTheme.info),
                    const Divider(height: 18),
                    FilaValor('Efectivo esperado', dinero(r.efectivoEsperado),
                        destacado: true),
                    FilaValor('Balones entregados', '${r.balonesEntregados}'),
                    FilaValor('Balones devueltos', '${r.balonesDevueltos}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          Text('¿Cuánto dinero entregas?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          TextFormField(
            controller: _efectivoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Efectivo entregado',
              prefixText: 'S/ ',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (r != null) ...[
            const SizedBox(height: 8),
            _diferenciaWidget(r),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _yapeCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Yape declarado',
              prefixText: 'S/ ',
              prefixIcon: Icon(Icons.phone_android_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _observacionesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observaciones (opcional)',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _guardando ? null : _declarar,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(_guardando ? 'Declarando…' : 'Declarar rendición'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppTheme.success,
            ),
          ),
        ],
      ),
    );
  }
}
