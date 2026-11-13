/// Caja del día: fondo, ingresos, egresos y balance esperado.
///
/// Los cobros de los pedidos entran solos a la caja (trigger de la base de
/// datos), así que aquí no se duplica nada: solo se muestra.
/// Solo ADMIN (RLS lo garantiza).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/caja_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class CajaPage extends ConsumerStatefulWidget {
  const CajaPage({super.key});

  @override
  ConsumerState<CajaPage> createState() => _CajaPageState();
}

class _CajaPageState extends ConsumerState<CajaPage> {
  Map<String, dynamic>? _caja;
  List<Map<String, dynamic>> _movimientos = [];
  ResumenCaja _resumen = const ResumenCaja();
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final caja = await cajaRepo.cajaAbierta();
      final movs = caja == null
          ? <Map<String, dynamic>>[]
          : await cajaRepo.movimientos(caja['id'] as String);
      final resumen = await cajaRepo.resumen(caja: caja);
      if (!mounted) return;
      setState(() {
        _caja = caja;
        _movimientos = movs;
        _resumen = resumen;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _error(traducirError(e, contexto: 'No pudimos cargar la caja').mensaje);
    }
  }

  Future<void> _abrirCaja() async {
    final ctrl = TextEditingController(text: '0.00');
    final fondo = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abrir caja'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Dinero en caja (S/)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text) ?? 0),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (fondo == null) return;
    final auth = ref.read(authProvider);
    try {
      await cajaRepo.abrir(
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        fondoInicial: fondo,
      );
      _cargar();
    } catch (e) {
      _error(traducirError(e, contexto: 'No pudimos abrir la caja').mensaje);
    }
  }

  Future<void> _movimientoManual({required bool esIngreso}) async {
    if (_caja == null) return;
    final montoCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esIngreso ? 'Registrar ingreso' : 'Registrar gasto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto (S/)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) {
      montoCtrl.dispose();
      descCtrl.dispose();
      return;
    }
    final monto = double.tryParse(montoCtrl.text) ?? 0;
    final descripcion = descCtrl.text.trim();
    montoCtrl.dispose();
    descCtrl.dispose();
    if (monto <= 0) {
      _error('El monto debe ser mayor a cero.');
      return;
    }
    final auth = ref.read(authProvider);
    try {
      if (esIngreso) {
        await cajaRepo.registrarIngreso(
          empresaId: auth.empresaId!,
          usuarioId: auth.usuarioId!,
          cajaId: _caja!['id'] as String,
          monto: monto,
          descripcion: descripcion,
        );
      } else {
        await cajaRepo.registrarGasto(
          empresaId: auth.empresaId!,
          usuarioId: auth.usuarioId!,
          cajaId: _caja!['id'] as String,
          monto: monto,
          descripcion: descripcion.isEmpty ? 'Gasto' : descripcion,
        );
      }
      _cargar();
    } catch (e) {
      _error(traducirError(e, contexto: 'No pudimos registrar el movimiento').mensaje);
    }
  }

  Future<void> _cerrarCaja() async {
    final ctrl = TextEditingController(text: _resumen.saldo.toStringAsFixed(2));
    final declarado = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar caja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Según el sistema deberías tener ${dinero(_resumen.saldo)}',
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Dinero contado (S/)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text)),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (declarado == null) return;
    final auth = ref.read(authProvider);
    try {
      await cajaRepo.cerrar(
        cajaId: _caja!['id'] as String,
        usuarioId: auth.usuarioId!,
        montoDeclarado: declarado,
      );
      _cargar();
    } catch (e) {
      _error(traducirError(e, contexto: 'No pudimos cerrar la caja').mensaje);
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _labelOrigen(String o) => switch (o) {
        'MANUAL' => 'Manual',
        'GASTO' => 'Gasto',
        'COMBUSTIBLE' => 'Combustible',
        'PAGO' => 'Cobro',
        _ => o,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Caja')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _caja == null
              ? _CajaCerrada(onAbrir: _abrirCaja)
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      // ---- Resumen del dinero ----
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              FilaValor('Total cobrado', dinero(_resumen.totalCobrado),
                                  destacado: true),
                              FilaValor('Efectivo', dinero(_resumen.efectivo)),
                              FilaValor('Yape', dinero(_resumen.yape), color: AppTheme.info),
                              if (_resumen.otros > 0)
                                FilaValor('Otros', dinero(_resumen.otros)),
                              FilaValor('Deudas', dinero(_resumen.deudas),
                                  color: _resumen.deudas > 0 ? AppTheme.danger : null),
                              FilaValor('Gastos', dinero(_resumen.gastos), color: AppTheme.danger),
                              const Divider(height: 20),
                              FilaValor('Fondo inicial',
                                  dinero(_resumen.fondoInicial)),
                              FilaValor('Ingresos', dinero(_resumen.ingresos),
                                  color: AppTheme.success),
                              FilaValor('Egresos', dinero(_resumen.egresos),
                                  color: AppTheme.danger),
                              const Divider(height: 20),
                              FilaValor('Saldo', dinero(_resumen.saldo), destacado: true),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _movimientoManual(esIngreso: false),
                              icon: const Icon(Icons.remove_circle_outline, color: AppTheme.danger),
                              label: const Text('Gasto'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _movimientoManual(esIngreso: true),
                              icon: const Icon(Icons.add_circle_outline, color: AppTheme.success),
                              label: const Text('Ingreso'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _cerrarCaja,
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Cerrar caja del día'),
                      ),
                      const SizedBox(height: 20),
                      Text('Movimientos', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_movimientos.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Sin movimientos todavía.',
                                style: TextStyle(color: Colors.black54)),
                          ),
                        )
                      else
                        for (final m in _movimientos)
                          Card(
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                m['tipo'] == 'INGRESO'
                                    ? Icons.south_west
                                    : Icons.north_east,
                                color: m['tipo'] == 'INGRESO'
                                    ? AppTheme.success
                                    : AppTheme.danger,
                              ),
                              title: Text(m['descripcion'] as String? ??
                                  _labelOrigen(m['origen'] as String? ?? '')),
                              subtitle: Text(_labelOrigen(m['origen'] as String? ?? '')),
                              trailing: Text(
                                '${m['tipo'] == 'INGRESO' ? '+' : '-'}S/ ${(m['monto'] as num? ?? 0).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: m['tipo'] == 'INGRESO'
                                      ? AppTheme.success
                                      : AppTheme.danger,
                                ),
                              ),
                            ),
                          ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}

class _CajaCerrada extends StatelessWidget {
  final VoidCallback onAbrir;
  const _CajaCerrada({required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.point_of_sale_outlined, size: 56, color: Colors.black26),
        const SizedBox(height: 16),
        const Center(
          child: Text('La caja está cerrada.\nÁbrela para registrar el dinero del día.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onAbrir,
          icon: const Icon(Icons.lock_open),
          label: const Text('Abrir caja'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: AppTheme.primary,
          ),
        ),
      ],
    );
  }
}
