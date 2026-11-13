import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import 'motorizado_form_page.dart';

/// Lista de motorizados de la empresa (solo ADMIN).
/// RLS se encarga de mostrar solo los de la empresa del usuario.
class MotorizadosPage extends ConsumerStatefulWidget {
  const MotorizadosPage({super.key});

  @override
  ConsumerState<MotorizadosPage> createState() => _MotorizadosPageState();
}

class _MotorizadosPageState extends ConsumerState<MotorizadosPage> {
  List<Map<String, dynamic>> _motorizados = [];
  List<Map<String, dynamic>> _vehiculos = [];
  bool _cargando = true;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final results = await Future.wait([
        _sb.from('perfiles')
            .select('id, nombre, telefono, activo')
            .eq('rol', 'MOTORIZADO')
            .order('nombre'),
        _sb.from('vehiculos').select('id, nombre, repartidor_id'),
      ]);
      if (!mounted) return;
      setState(() {
        _motorizados = List<Map<String, dynamic>>.from(results[0] as List);
        _vehiculos = List<Map<String, dynamic>>.from(results[1] as List);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _mostrarError('No pudimos cargar los motorizados. Revisa tu conexión.');
    }
  }

  String? _vehiculoDe(String usuarioId) {
    for (final v in _vehiculos) {
      if (v['repartidor_id'] == usuarioId) return v['nombre'] as String?;
    }
    return null;
  }

  Future<void> _abrirFormulario([Map<String, dynamic>? motorizado]) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MotorizadoFormPage(
          motorizado: motorizado,
          vehiculos: _vehiculos,
        ),
      ),
    );
    if (cambio == true) _cargar();
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Motorizados')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Agregar'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _motorizados.isEmpty
              ? const _EstadoVacio()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _motorizados.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final m = _motorizados[i];
                      final vehiculo = _vehiculoDe(m['id'] as String);
                      final activo = m['activo'] as bool? ?? true;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                            child: Text(
                              (m['nombre'] as String? ?? '?')[0].toUpperCase(),
                              style: const TextStyle(color: AppTheme.primary),
                            ),
                          ),
                          title: Text(m['nombre'] as String? ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [
                              if (m['telefono'] != null) m['telefono'],
                              if (vehiculo != null) '🚚 $vehiculo',
                            ].join('  ·  '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!activo)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Text('Inactivo',
                                      style: TextStyle(color: AppTheme.danger, fontSize: 12)),
                                ),
                              IconButton(
                                tooltip: 'Editar',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _abrirFormulario(m),
                              ),
                            ],
                          ),
                          onTap: () => _abrirFormulario(m),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Icon(Icons.delivery_dining_outlined, size: 56, color: Colors.black26),
        SizedBox(height: 12),
        Center(
          child: Text(
            'No tienes motorizados registrados.\nToca "Agregar" para crear el primero.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      ],
    );
  }
}
