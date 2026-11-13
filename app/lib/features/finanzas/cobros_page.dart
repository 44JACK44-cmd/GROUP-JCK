/// Registro de cobros y pagos de clientes + historial.
///
/// Un cobro guarda: monto, método (efectivo, Yape, …), fecha, hora y el
/// usuario que lo registró. Un cobro no se registra dos veces.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/data/clientes_repo.dart';
import '../../core/data/pagos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class CobrosPage extends ConsumerStatefulWidget {
  const CobrosPage({super.key});

  @override
  ConsumerState<CobrosPage> createState() => _CobrosPageState();
}

class _CobrosPageState extends ConsumerState<CobrosPage> {
  List<Map<String, dynamic>> _pagos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final data = await pagosRepo.listar(limite: 100);
      if (!mounted) return;
      setState(() {
        _pagos = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos cargar los cobros').mensaje)),
      );
    }
  }

  Future<void> _registrar() async {
    final datos = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CobroSheet(),
    );
    if (datos == null) return;

    final auth = ref.read(authProvider);
    try {
      await pagosRepo.registrar(
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        clienteId: datos['clienteId'] as String,
        monto: datos['monto'] as double,
        metodo: datos['metodo'] as String,
      );
      _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cobro registrado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos registrar el cobro').mensaje)),
      );
    }
  }

  double get _totalHoy {
    final hoy = DateTime.now();
    return _pagos
        .where((p) {
          final f = parseFecha(p['fecha']);
          return f != null &&
              f.day == hoy.day &&
              f.month == hoy.month &&
              f.year == hoy.year;
        })
        .fold(0.0, (s, p) => s + (p['monto'] as num).toDouble());
  }

  double get _yapeHoy {
    final hoy = DateTime.now();
    return _pagos
        .where((p) {
          final f = parseFecha(p['fecha']);
          return p['metodo'] == 'YAPE' &&
              f != null &&
              f.day == hoy.day &&
              f.month == hoy.month &&
              f.year == hoy.year;
        })
        .fold(0.0, (s, p) => s + (p['monto'] as num).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cobros'),
        actions: [
          IconButton(
            tooltip: 'Ver deudas',
            onPressed: () => context.push('/deudas'),
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _registrar,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Cobrar'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TarjetaMetrica(
                          titulo: 'Cobrado hoy',
                          valor: dinero(_totalHoy, conDecimales: false),
                          icono: Icons.today_outlined,
                          color: AppTheme.success,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TarjetaMetrica(
                          titulo: 'Yape hoy',
                          valor: dinero(_yapeHoy, conDecimales: false),
                          icono: Icons.smartphone_outlined,
                          color: AppTheme.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Historial', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_pagos.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Sin cobros registrados.',
                            style: TextStyle(color: Colors.black54)),
                      ),
                    )
                  else
                    for (final p in _pagos)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            p['metodo'] == 'YAPE'
                                ? Icons.smartphone_outlined
                                : Icons.payments_outlined,
                            color: p['metodo'] == 'YAPE' ? AppTheme.info : AppTheme.success,
                          ),
                          title: Text(
                            (p['clientes'] as Map?)?['nombre'] as String? ?? 'Cliente',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${fechaRelativa(parseFecha(p['fecha'] as String?))}  ·  '
                            '${metodoPago(p['metodo'] as String?)}',
                          ),
                          trailing: Text(dinero((p['monto'] as num? ?? 0)),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, color: AppTheme.success)),
                        ),
                      ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _CobroSheet extends StatefulWidget {
  const _CobroSheet();

  @override
  State<_CobroSheet> createState() => _CobroSheetState();
}

class _CobroSheetState extends State<_CobroSheet> {
  final _busquedaCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  List<Map<String, dynamic>> _sugerencias = [];
  Map<String, dynamic>? _cliente;
  String _metodo = 'EFECTIVO';
  bool _buscando = false;

  static const _metodos = {
    'EFECTIVO': '💵 Efectivo',
    'YAPE': '📱 Yape',
    'PLIN': '📱 Plin',
    'TRANSFERENCIA': '🏦 Transferencia',
    'OTRO': '💳 Otro',
  };

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar(String texto) async {
    final q = texto.trim();
    if (q.length < 2) {
      setState(() => _sugerencias = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final data = await clientesRepo.buscar(q);
      if (!mounted) return;
      setState(() {
        _sugerencias = data;
        _buscando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _confirmar() {
    final monto = double.tryParse(_montoCtrl.text) ?? 0;
    if (monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto debe ser mayor a cero.')),
      );
      return;
    }
    Navigator.of(context).pop({
      'clienteId': _cliente!['id'],
      'monto': monto,
      'metodo': _metodo,
    });
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
            const Text('Registrar cobro',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (_cliente == null) ...[
              TextField(
                controller: _busquedaCtrl,
                onChanged: _buscar,
                decoration: InputDecoration(
                  hintText: 'Buscar cliente',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscando
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              for (final s in _sugerencias)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(s['nombre'] as String? ?? ''),
                  subtitle: Text(s['telefono'] as String? ?? ''),
                  onTap: () => setState(() {
                    _cliente = s;
                    _sugerencias = [];
                    _busquedaCtrl.clear();
                  }),
                ),
            ] else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    (_cliente!['nombre'] as String? ?? '?')[0].toUpperCase(),
                    style: const TextStyle(color: AppTheme.primary),
                  ),
                ),
                title: Text(_cliente!['nombre'] as String? ?? ''),
                trailing: TextButton(
                  onPressed: () => setState(() => _cliente = null),
                  child: const Text('Cambiar'),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(prefixText: 'S/ ', labelText: 'Monto'),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _cliente == null ? null : _confirmar,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Guardar cobro'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
