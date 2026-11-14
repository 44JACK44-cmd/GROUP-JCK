/// Ajustes del dispositivo y de conexión.
///
/// Disponible **antes** de iniciar sesión (engranaje en la pantalla de
/// bienvenida y de login) y también después. Nunca muestra opciones
/// administrativas, claves secretas ni credenciales: solo estado real,
/// preferencias locales del dispositivo e información de versión.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../core/config.dart';
import '../../core/update/app_update_service.dart';

/// Preferencias locales (se guardan en el dispositivo, nunca en la nube).
class AjustesPrefs {
  AjustesPrefs._();

  static const _kMapaInterno = 'ajustes_mapa_dentro_app';
  static const _kAudio = 'ajustes_asistente_voz';

  static Future<bool> mapaDentroDeApp() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kMapaInterno) ?? false;
  }

  static Future<void> setMapaDentroDeApp(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kMapaInterno, v);
  }

  static Future<bool> asistenteDeVoz() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAudio) ?? true;
  }

  static Future<void> setAsistenteDeVoz(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAudio, v);
  }
}

enum EstadoPrueba { pendiente, probando, ok, fallido }

class AjustesPage extends StatefulWidget {
  const AjustesPage({super.key});

  @override
  State<AjustesPage> createState() => _AjustesPageState();
}

class _AjustesPageState extends State<AjustesPage> {
  // Conexión
  EstadoPrueba _estadoCon = EstadoPrueba.pendiente;
  int? _latencia;
  String? _errorCon;

  // Diagnóstico
  bool _diagnosticando = false;
  final List<String> _diagnostico = [];

  // Dispositivo
  bool _serviciosUbicacion = false;
  String _permisoUbicacion = 'Comprobando…';
  bool _puedePedirUbicacion = false;

  // Preferencias locales
  bool _mapaInterno = false;
  bool _voz = true;

  // Versión
  String _versionLocal = '…';
  String _build = '';
  String? _versionServidor;
  bool? _hayActualizacion;

  String get _host {
    final u = Uri.tryParse(supabaseUrl);
    return u?.host.isEmpty ?? true ? supabaseUrl : u!.host;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    await Future.wait([_cargarVersion(), _cargarUbicacion(), _cargarPreferencias()]);
    if (mounted) await _probarConexion(silencioso: true);
  }

  Future<void> _cargarVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionLocal = 'v${info.version}';
        _build = info.buildNumber;
      });
    } catch (_) {
      if (mounted) setState(() => _versionLocal = 'No disponible');
    }

    final remota = await AppUpdateService.fetchLatestVersion();
    if (!mounted) return;
    if (remota == null) {
      setState(() => _versionServidor = null);
      return;
    }
    setState(() {
      _versionServidor = 'v${remota.versionName}';
      _hayActualizacion = null; // se resuelve abajo
    });
    try {
      final nueva = await AppUpdateService.hayNuevaVersion(remota);
      if (mounted) setState(() => _hayActualizacion = nueva);
    } catch (_) {
      if (mounted) setState(() => _hayActualizacion = null);
    }
  }

  Future<void> _cargarUbicacion() async {
    bool servicios = false;
    String permiso = 'Desconocido';
    bool puedePedir = false;
    try {
      servicios = await Geolocator.isLocationServiceEnabled();
      if (!servicios) {
        permiso = 'Servicios de ubicación apagados';
        puedePedir = true;
      } else {
        final p = await Geolocator.checkPermission();
        switch (p) {
          case LocationPermission.denied:
            permiso = 'Permiso denegado';
            puedePedir = true;
          case LocationPermission.deniedForever:
            permiso = 'Permiso bloqueado (denegado para siempre)';
            puedePedir = true;
          case LocationPermission.whileInUse:
          case LocationPermission.always:
            permiso = 'Concedido';
          case LocationPermission.unableToDetermine:
            permiso = 'Sin determinar';
            puedePedir = true;
        }
      }
    } catch (_) {
      permiso = 'No se pudo comprobar';
    }
    if (!mounted) return;
    setState(() {
      _serviciosUbicacion = servicios;
      _permisoUbicacion = permiso;
      _puedePedirUbicacion = puedePedir;
    });
  }

  Future<void> _cargarPreferencias() async {
    final mapa = await AjustesPrefs.mapaDentroDeApp();
    final voz = await AjustesPrefs.asistenteDeVoz();
    if (!mounted) return;
    setState(() {
      _mapaInterno = mapa;
      _voz = voz;
    });
  }

  /// Prueba real contra Supabase: mide la latencia de la API REST.
  Future<void> _probarConexion({bool silencioso = false}) async {
    if (_estadoCon == EstadoPrueba.probando) return;
    if (!silencioso && mounted) {
      setState(() {
        _estadoCon = EstadoPrueba.probando;
        _errorCon = null;
      });
    }

    final reloj = Stopwatch()..start();
    try {
      final uri = Uri.parse(
          '$supabaseUrl/rest/v1/app_versiones?id=eq.1&select=version_code');
      final r = await http
          .get(uri, headers: {'apikey': supabaseAnonKey})
          .timeout(const Duration(seconds: 8));
      reloj.stop();
      if (!mounted) return;
      if (r.statusCode == 200) {
        setState(() {
          _estadoCon = EstadoPrueba.ok;
          _latencia = reloj.elapsedMilliseconds;
          _errorCon = null;
        });
      } else {
        setState(() {
          _estadoCon = EstadoPrueba.fallido;
          _latencia = reloj.elapsedMilliseconds;
          _errorCon = 'El servidor respondió código ${r.statusCode}.';
        });
      }
    } catch (e) {
      reloj.stop();
      if (!mounted) return;
      setState(() {
        _estadoCon = EstadoPrueba.fallido;
        _latencia = reloj.elapsedMilliseconds;
        _errorCon = 'Sin respuesta del servidor. Revisa tu Internet.';
      });
    }
  }

  Future<void> _solicitarUbicacion() async {
    if (!_serviciosUbicacion) {
      await Geolocator.openLocationSettings();
      await _cargarUbicacion();
      return;
    }
    try {
      await Geolocator.requestPermission();
    } catch (_) {
      // Ignorado: el estado real se vuelve a leer abajo.
    }
    await _cargarUbicacion();
  }

  Future<void> _ejecutarDiagnostico() async {
    if (_diagnosticando) return;
    setState(() {
      _diagnosticando = true;
      _diagnostico.clear();
    });

    final List<String> resultados = [];

    // 1. Red del dispositivo
    try {
      final con = await Connectivity().checkConnectivity();
      final hayRed = con.any((t) =>
          t == ConnectivityResult.mobile ||
          t == ConnectivityResult.wifi ||
          t == ConnectivityResult.ethernet);
      resultados.add(hayRed
          ? '✓ Red del dispositivo: conectada'
          : '✗ Red del dispositivo: sin conexión');
    } catch (_) {
      resultados.add('• Red del dispositivo: no se pudo comprobar');
    }

    // 2. Servidor Supabase (latencia real)
    await _probarConexion(silencioso: true);
    switch (_estadoCon) {
      case EstadoPrueba.ok:
        final ms = _latencia ?? 0;
        resultados.add('✓ Servidor Supabase: responde en $ms ms');
      case EstadoPrueba.fallido:
        resultados.add('✗ Servidor Supabase: ${_errorCon ?? 'sin respuesta'}');
      default:
        resultados.add('• Servidor Supabase: sin comprobar');
    }

    // 3. Versión publicada
    if (_versionServidor == null) {
      resultados.add('✗ Actualizaciones: no se pudo leer la versión publicada');
    } else if (_hayActualizacion == true) {
      resultados.add(
          '! Actualización disponible: $_versionLocal → $_versionServidor');
    } else if (_hayActualizacion == false) {
      resultados.add('✓ Versión: $_versionLocal (actualizada)');
    } else {
      resultados.add('• Versión publicada: $_versionServidor');
    }

    // 4. Ubicación
    if (_permisoUbicacion == 'Concedido') {
      resultados.add('✓ Permiso de ubicación: concedido');
    } else {
      resultados.add('! Permiso de ubicación: $_permisoUbicacion');
    }

    // 5. Preferencias locales
    resultados.add('• Mapa dentro de la app: '
        '${_mapaInterno ? 'activado' : 'desactivado (OpenStreetMap)'}');
    resultados.add('• Asistente de voz: ${_voz ? 'activado' : 'desactivado'}');

    if (!mounted) return;
    setState(() {
      _diagnostico.addAll(resultados);
      _diagnosticando = false;
    });
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _seccion(
            context,
            titulo: 'Conexión con el servidor',
            icono: Icons.cloud_outlined,
            hijo: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fila('Servidor', _host),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _chipEstado(),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _estadoCon == EstadoPrueba.probando
                          ? null
                          : () => _probarConexion(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Probar'),
                    ),
                  ],
                ),
                if (_errorCon != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _errorCon!,
                      style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                    ),
                  ),
                if (_latencia != null && _estadoCon == EstadoPrueba.ok)
                  Text(
                    'Última respuesta: $_latencia ms',
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
              ],
            ),
          ),
          _seccion(
            context,
            titulo: 'Mapas y navegación',
            icono: Icons.map_outlined,
            hijo: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Navegar dentro de la app',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _mapaInterno
                        ? 'Activado: la ruta se muestra en la pantalla de la app.'
                        : 'Desactivado: se usa OpenStreetMap integrado.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  value: _mapaInterno,
                  onChanged: (v) async {
                    await AjustesPrefs.setMapaDentroDeApp(v);
                    if (mounted) setState(() => _mapaInterno = v);
                  },
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                const Text(
                  'Mapa actual: OpenStreetMap (sin clave). '
                  'Google Maps se activará automáticamente cuando se configure '
                  'una API key válida; si no la hay, seguirá este mapa.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ],
            ),
          ),
          _seccion(
            context,
            titulo: 'Permisos de ubicación',
            icono: Icons.my_location_outlined,
            hijo: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fila('Estado', _permisoUbicacion),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _puedePedirUbicacion
                            ? _solicitarUbicacion
                            : null,
                        icon: const Icon(Icons.location_searching, size: 18),
                        label: Text(_permisoUbicacion == 'Concedido'
                            ? 'Permiso concedido'
                            : 'Solicitar permiso'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Se usa para marcar la ubicación del cliente y calcular la ruta.',
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
          _seccion(
            context,
            titulo: 'Audio y navegación',
            icono: Icons.volume_up_outlined,
            hijo: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Asistente de voz',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'Indicaciones habladas durante la ruta. El volumen '
                    'se controla con los botones del teléfono.',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: _voz,
                  onChanged: (v) async {
                    await AjustesPrefs.setAsistenteDeVoz(v);
                    if (mounted) setState(() => _voz = v);
                  },
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                const Text(
                  'Las instrucciones se generan con la ruta real. '
                  'Esta preferencia se aplica en cuanto esté disponible '
                  'el asistente de voz.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ],
            ),
          ),
          _seccion(
            context,
            titulo: 'Versión',
            icono: Icons.info_outline,
            hijo: Column(
              children: [
                _fila('Aplicación', _build.isEmpty ? _versionLocal : '$_versionLocal (build $_build)'),
                _fila('Versión publicada', _versionServidor ?? 'No disponible'),
                if (_hayActualizacion == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.system_update, color: AppTheme.warning, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Hay una versión nueva ($_versionServidor). '
                            'Inicia sesión y busca "Buscar actualización".',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _seccion(
            context,
            titulo: 'Diagnóstico',
            icono: Icons.troubleshoot,
            hijo: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: _diagnosticando ? null : _ejecutarDiagnostico,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  icon: _diagnosticando
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_diagnosticando
                      ? 'Comprobando…'
                      : 'Ejecutar diagnóstico completo'),
                ),
                if (_diagnostico.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final linea in _diagnostico)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(linea,
                          style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'GasApp no guarda claves secretas en el teléfono.\n'
              'Los ajustes de administración se encuentran dentro de la app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Colors.black38),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _chipEstado() {
    switch (_estadoCon) {
      case EstadoPrueba.probando:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Probando…', style: TextStyle(fontSize: 13)),
          ],
        );
      case EstadoPrueba.ok:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppTheme.success, size: 16),
            const SizedBox(width: 6),
            Text('Conectado', style: const TextStyle(fontSize: 13)),
          ],
        );
      case EstadoPrueba.fallido:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
            SizedBox(width: 6),
            Text('Sin conexión', style: TextStyle(fontSize: 13)),
          ],
        );
      case EstadoPrueba.pendiente:
        return const Text('Sin comprobar', style: TextStyle(fontSize: 13));
    }
  }

  Widget _fila(String etiqueta, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(etiqueta,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ),
        Expanded(
          child: Text(valor,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _seccion(BuildContext context,
      {required String titulo, required IconData icono, required Widget hijo}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            hijo,
          ],
        ),
      ),
    );
  }
}
