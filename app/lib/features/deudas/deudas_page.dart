/// Deudas de los clientes.
///
/// Lista de quien debe, cuánto debe y la acción de registrar un pago.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/clientes_repo.dart';
import '../../core/data/pagos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class DeudasPage extends ConsumerStatefulWidget {
  const DeudasPage({super.key});

  @override
  ConsumerState<DeudasPage> createState() => _DeudasPageState();
}

class _DeudasPageState extends ConsumerState<DeudasPage> {
  List<Map<String, dynamic>> _deudores = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final deudas = await clientesRepo.deudasGlobales();
      if (deudas.isEmpty) {
        if (!mounted) return;
        setState(() {
          _deudores = [];
          _cargando = false;
        });
        return;
      }
      final ids = deudas.keys.toList();
      final clientes = await sb
          .from('clientes')
          .select('id, nombre, telefono, direccion')
          .inFilter('id', ids);
      if (!mounted) return;
      final lista = <Map<String, dynamic>>[];
      for (final c in clientes) {
        final id = c['id'] as String;
        lista.add({...c, 'deuda': deudas[id] ?? 0});
      }
      lista.sort((a, b) =>
          ((b['deuda'] as num).toDouble()).compareTo((a['deuda'] as num).toDouble()));
      setState(() {
        _deudores = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos cargar las deudas').mensaje)),
      );
    }
  }

  double get _total =>
      _deudores.fold(0.0, (s, d) => s + ((d['deuda'] as num? ?? 0).toDouble()));

  Future<void> _registrarPago(Map<String, dynamic> cliente) async {
    final resultado = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PagoDeudaSheet(cliente: cliente),
    );
    if (resultado == null) return;

    final auth = ref.read(authProvider);
    try {
      await pagosRepo.registrar(
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        clienteId: cliente['id'] as String,
        monto: resultado['monto'] as double,
        metodo: resultado['metodo'] as String,
      );
      _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pago de ${dinero(resultado['monto'] as double)} registrado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos registrar el pago').mensaje)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deudas')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _deudores.isEmpty
              ? const EstadoVacio(
                  icono: Icons.verified_outlined,
                  titulo: 'Nadie debe dinero',
                  mensaje: 'Las deudas aparecen aquí cuando alguien se queda debiendo.',
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.account_balance_wallet_outlined,
                                  size: 36, color: AppTheme.danger),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Total por cobrar',
                                        style: TextStyle(color: Colors.black54)),
                                    Text(dinero(_total),
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.danger,
                                        )),
                                    Text('${_deudores.length} cliente(s)',
                                        style: const TextStyle(color: Colors.black54)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final d in _deudores)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          d['nombre'] as String? ?? 'Cliente',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                      ),
                                      Text(
                                        'Debe ${dinero((d['deuda'] as num? ?? 0).toDouble())}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.danger,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if ((d['telefono'] as String? ?? '').isNotEmpty)
                                    Text(d['telefono'] as String,
                                        style: const TextStyle(color: Colors.black54)),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _registrarPago(d),
                                      icon: const Icon(Icons.payments_outlined),
                                      label: const Text('Registrar pago'),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size.fromHeight(44),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

/// Hoja para registrar el pago de una deuda.
class _PagoDeudaSheet extends StatefulWidget {
  final Map<String, dynamic> cliente;

  const _PagoDeudaSheet({required this.cliente});

  @override
  State<_PagoDeudaSheet> createState() => _PagoDeudaSheetState();
}

class _PagoDeudaSheetState extends State<_PagoDeudaSheet> {
  late final TextEditingController _montoCtrl = TextEditingController(
    text: ((widget.cliente['deuda'] as num? ?? 0).toDouble()).toStringAsFixed(2),
  );
  String _metodo = 'EFECTIVO';

  static const _metodos = {
    'EFECTIVO': '💵 Efectivo',
    'YAPE': '📱 Yape',
    'PLIN': '📱 Plin',
    'TRANSFERENCIA': '🏦 Transferencia',
    'OTRO': '💳 Otro',
  };

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final monto = double.tryParse(_montoCtrl.text) ?? 0;
    if (monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto debe ser mayor a cero.')),
      );
      return;
    }
    Navigator.of(context).pop({'monto': monto, 'metodo': _metodo});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cobrar a ${widget.cliente['nombre']}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(prefixText: 'S/ ', labelText: 'Monto'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _metodos.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _metodo == e.key,
                    selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: _metodo == e.key ? AppTheme.primary : Colors.black87,
                      fontWeight: _metodo == e.key ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => _metodo = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _confirmar,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Registrar pago'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
