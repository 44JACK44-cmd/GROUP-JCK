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

/// Dominio de correo interno: el usuario escribe su teléfono
/// (ej. 999888777) y se convierte en 999888777@grupojck.app
const String emailDomain = 'grupojck.app';
