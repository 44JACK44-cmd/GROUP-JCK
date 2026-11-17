import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import 'cliente_detalle_page.dart';
import 'cliente_form_page.dart';

/// Lista de clientes de la empresa con búsqueda por nombre,
/// teléfono o dirección. RLS muestra solo los de la empresa.
class ClientesPage extends ConsumerStatefulWidget {
  ClientesPage({super.key});

  @override
  ConsumerState<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends ConsumerState<ClientesPage> {
  final _busquedaCtrl = TextEditingController();
  List<Map<String, dynamic>> _clientes = [];
  bool _cargando = true;
  String _filtro = '';

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final data = await _sb
          .from('clientes')
          .select('id, nombre, telefono, tipo, direccion, activo')
          .eq('activo', true)
          .order('nombre');
      if (!mounted) return;
      setState(() {
        _clientes = List<Map<String, dynamic>>.from(data);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _mostrarError('No pudimos cargar los clientes. Revisa tu conexión.');
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    if (_filtro.isEmpty) return _clientes;
    final q = _filtro.toLowerCase();
    return _clientes.where((c) {
      return (c['nombre'] as String? ?? '').toLowerCase().contains(q) ||
          (c['telefono'] as String? ?? '').contains(q) ||
          (c['direccion'] as String? ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _abrirFormulario([Map<String, dynamic>? cliente]) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ClienteFormPage(cliente: cliente)),
    );
    if (cambio == true) _cargar();
  }

  Future<void> _abrirDetalle(Map<String, dynamic> cliente) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ClienteDetallePage(cliente: cliente)),
    );
    if (cambio == true) _cargar();
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      appBar: AppBar(title: Text('Clientes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        backgroundColor: AppTheme.primary,
        icon: Icon(Icons.person_add_alt_1),
        label: Text('Nuevo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _busquedaCtrl,
              onChanged: (v) => setState(() => _filtro = v.trim()),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, teléfono o dirección',
                prefixIcon: Icon(Icons.search),
                suffixIcon: _filtro.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () {
                          _busquedaCtrl.clear();
                          setState(() => _filtro = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: _cargando
                ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : lista.isEmpty
                    ? _EstadoVacio(tieneBusqueda: _filtro.isNotEmpty)
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.separated(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 90),
                          itemCount: lista.length,
                          separatorBuilder: (_, i) => SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final c = lista[i];
                            final subtitulo = [
                              if (c['telefono'] != null) c['telefono'],
                              if (c['direccion'] != null &&
                                  (c['direccion'] as String).isNotEmpty)
                                c['direccion'],
                            ].join('  ·  ');
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                                  child: Text(
                                    (c['nombre'] as String? ?? '?')[0].toUpperCase(),
                                    style: TextStyle(color: AppTheme.primary),
                                  ),
                                ),
                                title: Text(c['nombre'] as String? ?? '',
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: subtitulo.isEmpty
                                    ? null
                                    : Text(subtitulo,
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Icon(Icons.chevron_right),
                                onTap: () => _abrirDetalle(c),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  final bool tieneBusqueda;
  const _EstadoVacio({required this.tieneBusqueda});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(height: 120),
        Icon(Icons.people_outline, size: 56, color: AppColors.textoMuted),
        SizedBox(height: 12),
        Center(
          child: Text(
            tieneBusqueda
                ? 'Ningún cliente coincide con la búsqueda.'
                : 'No tienes clientes registrados.\nToca "Nuevo" para agregar el primero.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textoSecundario),
          ),
        ),
      ],
    );
  }
}