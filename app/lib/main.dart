import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/theme.dart';
import 'core/config.dart';
import 'core/update/app_update_service.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_empresa_page.dart';
import 'features/auth/welcome_page.dart';
import 'features/balones/balones_page.dart';
import 'features/clientes/clientes_page.dart';
import 'features/deudas/deudas_page.dart';
import 'features/finanzas/caja_page.dart';
import 'features/finanzas/cobros_page.dart';
import 'features/finanzas/combustible_page.dart';
import 'features/home/home_moto_page.dart';
import 'features/home/home_page.dart';
import 'features/mas/mas_page.dart';
import 'features/motorizados/motorizados_page.dart';
import 'features/pedidos/historial_page.dart';
import 'features/pedidos/mis_pedidos_page.dart';
import 'features/pedidos/nuevo_pedido_page.dart';
import 'features/pedidos/pedidos_page.dart';
import 'features/rendicion/rendicion_page.dart';
import 'features/reportes/reportes_page.dart';
import 'features/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const ProviderScope(child: GasApp()));
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

class GasApp extends ConsumerStatefulWidget {
  const GasApp({super.key});

  static const _rutasPublicas = {'/welcome', '/login', '/registro-empresa'};

  /// Pestañas que solo puede usar el administrador.
  static const _rutasAdmin = {'/pedidos', '/clientes', '/cobros', '/mas'};

  @override
  ConsumerState<GasApp> createState() => _GasAppState();
}

class _GasAppState extends ConsumerState<GasApp> {
  bool _updateCheckDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificarActualizacion());
  }

  // ---------- Actualización OTA ----------
  Future<void> _verificarActualizacion() async {
    if (_updateCheckDone || !mounted) return;
    _updateCheckDone = true;

    final remota = await AppUpdateService.fetchLatestVersion();
    if (remota == null || !mounted) return;
    if (!await AppUpdateService.hayNuevaVersion(remota) || !mounted) return;

    // Esperar a que el navigator exista (puede tardar tras el splash).
    for (var i = 0; i < 20 && _rootNavigatorKey.currentContext == null; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
    }
    if (!mounted) return;

    _mostrarDialogoUpdate(remota);
  }

  void _mostrarDialogoUpdate(VersionInfo remota) {
    final context = _rootNavigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      barrierDismissible: !remota.obligatoria,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva versión disponible'),
        content: Text(
          'Hay una nueva versión (v${remota.versionName}) de la app.'
          '${remota.notas != null && remota.notas!.isNotEmpty ? '\n\n${remota.notas}' : ''}\n\n'
          'Se descargará e instalará automáticamente.',
        ),
        actions: [
          if (!remota.obligatoria)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Luego'),
            ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _descargarEInstalar(remota);
            },
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  Future<void> _descargarEInstalar(VersionInfo remota) async {
    final context = _rootNavigatorKey.currentContext;
    if (context == null) return;

    final progreso = ValueNotifier<double>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Descargando actualización'),
        content: ValueListenableBuilder<double>(
          valueListenable: progreso,
          builder: (ctx, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Por favor espera, no cierres la app.'),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: p > 0 ? p : null),
              const SizedBox(height: 8),
              Text('${(p * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    );

    try {
      final apk = await AppUpdateService.descargarApk(remota.apkUrl, (p) {
        progreso.value = p;
      });
      progreso.dispose();
      if (!context.mounted) return;
      Navigator.of(context).pop(); // cerrar diálogo de progreso
      await AppUpdateService.instalar(apk);
    } catch (_) {
      progreso.dispose();
      if (!context.mounted) return;
      Navigator.of(context).pop(); // cerrar diálogo si sigue abierto
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo descargar la actualización. Inténtalo más tarde.')),
      );
    }
  }

  // ---------- Router ----------
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    final router = GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: '/welcome',
      redirect: (context, state) {
        final loc = state.matchedLocation;
        switch (auth.status) {
          case AuthStatus.cargando:
            return loc == '/splash' ? null : '/splash';
          case AuthStatus.noAutenticado:
            return GasApp._rutasPublicas.contains(loc) ? null : '/welcome';
          case AuthStatus.autenticado:
            if (GasApp._rutasPublicas.contains(loc) || loc == '/splash') {
              return '/inicio';
            }
            // El motorizado no entra a las pestañas de administración.
            if (auth.esMotorizado &&
                (GasApp._rutasAdmin.contains(loc) || loc == '/pedidos/nuevo')) {
              return '/mis-pedidos';
            }
            // El administrador usa su propio menú "Más".
            if (auth.esAdmin && loc == '/mas-moto') return '/mas';
            return null;
        }
      },
      routes: [
        GoRoute(path: '/splash', builder: (_, state) => const _Splash()),
        GoRoute(path: '/welcome', builder: (_, state) => const WelcomePage()),
        GoRoute(path: '/login', builder: (_, state) => const LoginPage()),
        GoRoute(path: '/registro-empresa', builder: (_, state) => const RegisterEmpresaPage()),

        // ------- Barra inferior (pestañas) -------
        ShellRoute(
          builder: (context, state, child) => AppShell(
            child: child,
            location: state.uri.path,
          ),
          routes: [
            GoRoute(path: '/inicio', builder: (_, state) => const _InicioPorRol()),
            GoRoute(path: '/pedidos', builder: (_, state) => const PedidosPage()),
            GoRoute(path: '/clientes', builder: (_, state) => const ClientesPage()),
            GoRoute(path: '/cobros', builder: (_, state) => const CobrosPage()),
            GoRoute(path: '/mas', builder: (_, state) => const MasPage()),
            GoRoute(path: '/mis-pedidos', builder: (_, state) => const MisPedidosPage()),
            GoRoute(path: '/historial', builder: (_, state) => const HistorialPage()),
            GoRoute(path: '/mas-moto', builder: (_, state) => const MasMotoPage()),
          ],
        ),
        // Ruta antigua: la pantalla de reparto ahora es "Mis pedidos".
        GoRoute(path: '/reparto', redirect: (_, __) => '/mis-pedidos'),

        // ------- Pantallas completas (sin barra inferior) -------
        GoRoute(path: '/pedidos/nuevo', builder: (_, state) => const NuevoPedidoPage()),
        GoRoute(path: '/balones', builder: (_, state) => const BalonesPage()),
        GoRoute(path: '/deudas', builder: (_, state) => const DeudasPage()),
        GoRoute(path: '/caja', builder: (_, state) => const CajaPage()),
        GoRoute(path: '/rendicion', builder: (_, state) => const RendicionPage()),
        GoRoute(path: '/reportes', builder: (_, state) => const ReportesPage()),
        GoRoute(path: '/motorizados', builder: (_, state) => const MotorizadosPage()),
        GoRoute(path: '/combustible', builder: (_, state) => const CombustiblePage()),
      ],
    );

    return MaterialApp.router(
      title: 'GasApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}

/// La pantalla de inicio depende del rol: el admin controla, el motorizado reparte.
class _InicioPorRol extends ConsumerWidget {
  const _InicioPorRol();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return auth.esMotorizado ? const HomeMotoPage() : const HomePage();
  }
}

/// Rutas/páginas que se abren como modal (fuera de la barra inferior).
/// Se usan con `abrirPagina` para no romper la navegación actual.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
  }
}
