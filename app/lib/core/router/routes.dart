abstract final class Routes {
  static const splash = '/';
  static const login = '/login';

  static const inicio = '/inicio';
  static const pedidos = '/pedidos';
  static const nuevoPedido = '/pedidos/nuevo';
  static const clientes = '/clientes';
  static const cobros = '/cobros';
  static const mas = '/mas';
  static const balones = '/mas/balones';
  static const combustible = '/mas/combustible';
  static const caja = '/mas/caja';
  static const reportes = '/mas/reportes';
  static const configuracion = '/mas/configuracion';

  static const entregas = '/entregas';
  static const repartoCobros = '/reparto/cobros';
  static const repartoMas = '/reparto/mas';
  static const repartoCombustible = '/reparto/mas/combustible';

  static const _adminPrefixes = [inicio, pedidos, clientes, cobros, mas];
  static const _repartidorPrefixes = [entregas, '/reparto'];

  static bool isAdminRoute(String loc) => _adminPrefixes.any(loc.startsWith);

  static bool isRepartidorRoute(String loc) => _repartidorPrefixes.any(loc.startsWith);
}
