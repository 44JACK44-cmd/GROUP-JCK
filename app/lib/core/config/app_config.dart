/// Configuración por entorno. Se define al compilar:
/// flutter build apk --dart-define=API_URL=https://api.midominio.pe
class AppConfig {
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static const connectTimeout = Duration(seconds: 10);
  static const receiveTimeout = Duration(seconds: 20);
}
