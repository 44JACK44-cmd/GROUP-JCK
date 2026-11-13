/// Control de balones y fierros.
///
/// Muestra quién tiene balones vacíos pendientes y permite registrar la
/// devolución cuando el cliente los devuelve. Nada se borra: cada devolución
/// es un movimiento nuevo (queda la trazabilidad).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/balones_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../auth/auth_controller.dart';

class BalonesPage extends ConsumerStatefulWidget {
  const BalonesPage({super.key});

  @override
  ConsumerState<BalonesPage> createState() => _BalonesPageState();
}

class _BalonesPageState extends ConsumerState<BalonesPage> {
  List<PendienteDevolucion> _balones = [];
  List<PendienteDevolucion> _fierros = [];
  List<Map<String, dynamic>> _movimientos = [];
  bool _cargando = true;
  bool _mostrarFierros = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final res = await Future.wait([
        balonesRepo.pendientesBalones(),
        balonesRepo.pendientesFierros(),
        balonesRepo.movimientos(limite: 30),
      ]);
      if (!mounted) return;
      setState(() {
        _balones = res[0] as List<PendienteDevolucion>;
        _fierros = res[1] as List<PendienteDevolucion>;
        _movimientos = res[2] as List<Map<String, dynamic>>;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos cargar los balones').mensaje)),
      );
    }
  }

  int get _totalBalones => _balones.fold(0, (s, p) => s + p.cantidad);

  Future<void> _registrarDevolucion(PendienteDevolucion pendiente, {bool esFierro = false}) async {
    final resultado = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DevolucionSheet(pendiente: pendiente, esFierro: esFierro),
    );
    if (resultado == null) return;

    final auth = ref.read(authProvider);
    try {
      if (esFierro) {
        await balonesRepo.registrarDevolucionFierro(
          empresaId: auth.empresaId!,
          usuarioId: auth.usuarioId!,
          clienteId: pendiente.clienteId,
          cantidad: resultado,
        );
      } else {
        await balonesRepo.registrarDevolucionBalon(
          empresaId: auth.empresaId!,
          usuarioId: auth.usuarioId!,
          clienteId: pendiente.clienteId,
          cantidad: resultado,
        );
      }
      _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Devolución registrada: $resultado ${esFierro ? 'fierro(s)' : 'balón(es)'}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos registrar la devolución').mensaje)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _mostrarFierros ? _fierros : _balones;
    return Scaffold(
      appBar: AppBar(title: const Text('Balones')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
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
                          Icon(
                            _mostrarFierros ? Icons.handyman_outlined : Icons.local_fire_department_outlined,
                            size: 36,
                            color: AppTheme.warning,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _mostrarFierros
                                      ? 'Fierros pendientes de devolución'
                                      : 'Balones vacíos pendientes',
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                Text(
                                  _mostrarFierros
                                      ? '${_fierros.fold(0, (s, p) => s + p.cantidad)}'
                                      : '$_totalBalones',
                                  style: const TextStyle(
                                      fontSize: 26, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Balones')),
                      ButtonSegment(value: true, label: Text('Fierros')),
                    ],
                    selected: {_mostrarFierros},
                    onSelectionChanged: (s) => setState(() => _mostrarFierros = s.first),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    lista.isEmpty
                        ? 'Sin pendientes'
                        : '${lista.length} cliente(s) con pendiente',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (lista.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Nadie tiene pendiente de devolución.',
                            style: TextStyle(color: Colors.black54)),
                      ),
                    )
                  else
                    for (final p in lista)
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
                                        p.nombre,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.warning.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(
                                        '${p.cantidad}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.warning,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if ((p.telefono ?? '').isNotEmpty)
                                  Text(p.telefono!,
                                      style: const TextStyle(color: Colors.black54)),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _registrarDevolucion(p, esFierro: _mostrarFierros),
                                    icon: const Icon(Icons.assignment_return_outlined),
                                    label: const Text('Registrar devolución'),
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
                  const SizedBox(height: 20),
                  Text('Movimientos recientes', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final m in _movimientos)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        m['tipo'] == 'ENTREGA_LLENO'
                            ? Icons.south_west
                            : Icons.north_east,
                        color: m['tipo'] == 'ENTREGA_LLENO'
                            ? AppTheme.primary
                            : AppTheme.success,
                        size: 20,
                      ),
                      title: Text(m['tipo'] == 'ENTREGA_LLENO'
                          ? 'Entrega de ${m['cantidad']} lleno(s)'
                          : 'Devolución de ${m['cantidad']} vacío(s)'),
                      subtitle: Text(
                        '${(m['clientes'] as Map?)?['nombre'] ?? ''} · ${fechaHora(parseFecha(m['fecha'] as String?))}',
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

/// Hoja para registrar la cantidad devuelta.
class _DevolucionSheet extends StatefulWidget {
  final PendienteDevolucion pendiente;
  final bool esFierro;

  const _DevolucionSheet({required this.pendiente, required this.esFierro});

  @override
  State<_DevolucionSheet> createState() => _DevolucionSheetState();
}

class _DevolucionSheetState extends State<_DevolucionSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: '${widget.pendiente.cantidad}');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final cant = int.tryParse(_ctrl.text) ?? 0;
    if (cant <= 0 || cant > widget.pendiente.cantidad) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cantidad inválida (1 a ${widget.pendiente.cantidad}).')),
      );
      return;
    }
    Navigator.of(context).pop(cant);
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.esFierro
                ? 'Devolución de fierro — ${widget.pendiente.nombre}'
                : 'Devolución de balón vacío — ${widget.pendiente.nombre}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Cantidad (máx. ${widget.pendiente.cantidad})',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _confirmar,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Registrar devolución'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
