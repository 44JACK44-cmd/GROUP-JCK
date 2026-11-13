import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/theme.dart';
import '../../core/update/app_update_service.dart';

/// Menú "Más": módulos secundarios del administrador.
class MasPage extends StatelessWidget {
  const MasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Tile(
            icono: Icons.local_fire_department_outlined,
            titulo: 'Balones',
            subtitulo: 'Control de balones prestados y devoluciones',
            color: AppTheme.warning,
            onTap: () => context.push('/balones'),
          ),
          _Tile(
            icono: Icons.point_of_sale_outlined,
            titulo: 'Caja',
            subtitulo: 'Dinero del día, gastos e ingresos',
            color: AppTheme.success,
            onTap: () => context.push('/caja'),
          ),
          _Tile(
            icono: Icons.payments_outlined,
            titulo: 'Cobros',
            subtitulo: 'Registrar pagos y ver historial',
            color: AppTheme.info,
            onTap: () => context.push('/cobros'),
          ),
          _Tile(
            icono: Icons.local_gas_station_outlined,
            titulo: 'Combustible',
            subtitulo: 'Gastos de gasolina por vehículo',
            color: AppTheme.warning,
            onTap: () => context.push('/combustible'),
          ),
          _Tile(
            icono: Icons.bar_chart_outlined,
            titulo: 'Reportes',
            subtitulo: 'Ventas, cobros y gastos del día y la semana',
            color: AppTheme.primary,
            onTap: () => context.push('/reportes'),
          ),
          _Tile(
            icono: Icons.delivery_dining_outlined,
            titulo: 'Motorizados',
            subtitulo: 'Tu equipo de reparto',
            color: AppTheme.primary,
            onTap: () => context.push('/motorizados'),
          ),
          _Tile(
            icono: Icons.people_outline,
            titulo: 'Clientes',
            subtitulo: 'Directorio de clientes',
            color: AppTheme.primary,
            onTap: () => context.push('/clientes'),
          ),
          const _UpdateTile(),
        ],
      ),
    );
  }
}

/// Tile "Buscar actualización": muestra la versión instalada y
/// permite forzar la revisión/descarga de la última versión.
class _UpdateTile extends ConsumerStatefulWidget {
  const _UpdateTile();

  @override
  ConsumerState<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<_UpdateTile> {
  String _version = '';
  bool _verificando = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = 'v${i.version}');
    });
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _verificar() async {
    if (_verificando) return;
    setState(() => _verificando = true);
    try {
      final remota = await AppUpdateService.fetchLatestVersion();
      if (remota == null) {
        _error('No pudimos conectar con el servidor. Inténtalo más tarde.');
        return;
      }
      if (!await AppUpdateService.hayNuevaVersion(remota)) {
        _error('Tienes la última versión ($_version).');
        return;
      }
      if (!mounted) return;
      final actualizar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nueva versión disponible'),
          content: Text(
            'Versión ${remota.versionName}'
            '${remota.notas != null && remota.notas!.isNotEmpty ? '\n\n${remota.notas}' : ''}\n\n'
            '¿Descargar e instalar ahora?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Luego')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Actualizar')),
          ],
        ),
      );
      if (actualizar != true || !mounted) return;
      await _descargar(remota);
    } catch (_) {
      _error('No pudimos verificar. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  Future<void> _descargar(VersionInfo remota) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Descargando actualización…'),
            SizedBox(height: 16),
            LinearProgressIndicator(),
          ],
        ),
      ),
    );
    try {
      final apk = await AppUpdateService.descargarApk(remota.apkUrl, (_) {});
      if (!mounted) return;
      Navigator.of(context).pop(); // cerrar diálogo de descarga
      final r = await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) _error('No se pudo abrir el instalador.');
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
      _error('No se pudo descargar. Inténtalo más tarde.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
          child: Icon(
            _verificando ? Icons.sync : Icons.system_update_alt,
            color: AppTheme.primary,
          ),
        ),
        title: const Text('Buscar actualización',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_version.isEmpty ? 'Revisar versión nueva' : '$_version · tocar para revisar'),
        trailing: _verificando
            ? const SizedBox(
                height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right),
        onTap: _verificando ? null : _verificar,
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final Color color;
  final VoidCallback onTap;

  const _Tile({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icono, color: color),
        ),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitulo, style: const TextStyle(color: Colors.black54)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
