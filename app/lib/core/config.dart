/// Credenciales del proyecto Supabase.
/// Se configuran al compilar:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// Para desarrollo local también puedes crear un archivo
/// `app/.env` o editar estos valores por defecto.
const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://kzhvutzkggcgrnalpcqs.supabase.co',
);

const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt6aHZ1dHprZ2djZ3JuYWxwY3FzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1Nzg4OTEsImV4cCI6MjExMDE1NDg5MX0.c7RCFTQOrEtT-3D2QjAWEXmUqepx02m5CCsRLyoj_6A',
);

/// Clave de Google Maps / Directions.
///
/// NUNCA se escribe en el código ni se sube al repositorio: se pasa al
/// compilar con
///   flutter build apk --dart-define=GOOGLE_MAPS_API_KEY=tu_clave
/// y para Android se inyecta además en el manifiesto desde
/// `android/local.properties` (`maps.apiKey=...`, archivo ignorado por git).
///
/// Si está vacía, la app sigue funcionando: muestra un mapa alternativo
/// (OpenStreetMap) con un aviso claro y permite abrir Google Maps externo.
const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// True si esta compilación trae clave de Google Maps.
bool get hayClaveGoogleMaps => googleMapsApiKey.trim().isNotEmpty;

/// Dominio de correo interno: el usuario escribe su teléfono
/// (ej. 999888777) y se convierte en 999888777@grupojck.app
const String emailDomain = 'grupojck.app';
