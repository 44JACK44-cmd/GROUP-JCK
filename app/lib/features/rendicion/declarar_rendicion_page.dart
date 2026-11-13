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
        _efectivoCtrl.text = data.efectivo.toStringAsFixed(2);
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
                    FilaValor('Cobrado', dinero(r.cobrado), destacado: true),
                    FilaValor('Efectivo esperado', dinero(r.efectivo)),
                    FilaValor('Yape esperado', dinero(r.yape)),
                    if (r.gastosTotal > 0)
                      FilaValor('Gastos', dinero(r.gastosTotal), color: AppTheme.danger),
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
          ),
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
