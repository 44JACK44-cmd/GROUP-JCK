# FASE 17 — Rediseño visual profundo

## TEMA

- **Modo oscuro real**: fondo `#0B0B0B`, superficie `#151515`, elevada `#1D1D1D`,
  borde `#2A2A2A`, texto `#F5F5F5` / `#B8B8B8` / `#858585`. El azul solo es
  acento (`#3B82F6`) para acciones, selección, enlaces e indicadores. Ya no hay
  fondos azulados.
- **Modo claro real**: fondo `#F7F7F7`, superficie `#FFFFFF`, borde `#E5E5E5`,
  texto `#171717` / `#525252` / `#737373`.
- **Sistema centralizado**: `core/theme/app_colors.dart` + `app/theme.dart`.
  Se migraron los colores hardcodeados (`Colors.black54/45/87`, bordes grises,
  fondos blancos) de 48 archivos al sistema de tema.
- **Contraste**: `textTheme` del tema define color de texto explícito para
  títulos, cuerpo y labels, en claro y oscuro. Ningún texto hereda blanco sobre
  fondo claro.
- **Persistencia**: `TemaApp` guarda Claro/Oscuro/Sistema en SharedPreferences y
  se aplica en `main()` antes de dibujar.
- **Cambio inmediato**: `ValueListenableBuilder` en `MaterialApp.router` +
  `themeAnimationDuration: 220 ms` con `Curves.easeInOut`. Afecta AppBar,
  fondo, tarjetas, botones, iconos, diálogos, sheets, formularios, listas,
  navegación y estados sin reiniciar ni cambiar de pantalla.

## ANIMACIONES

- **Login**: entrada escalonada (logo fade+escala, título, formulario y botón)
  en 600 ms con `Interval` y `easeOut`.
- **Botones**: overlay/ripple global definido en `FilledButton`, `OutlinedButton`
  y `TextButton` del tema.
- **Navegación**: `FadeForwardsPageTransitionsBuilder` en Android/iOS.
- **Cambio de tema**: transición de 220 ms controlada por MaterialApp.
- **Movimientos/estados**: indicadores de carga y timeline existentes; se
  conservan y ahora respetan el tema.
- Duraciones centralizadas: `AppTheme.rapida` 140 ms, `normal` 220 ms,
  `lenta` 320 ms.

## NAVEGACIÓN

- ADMIN: Inicio · Pedidos · Clientes · **Caja** · Más.
- MOTORIZADO: Inicio · Pedidos · **Movimientos** · Más.
- Iconos Material consistentes (`home`, `receipt_long`, `people`,
  `account_balance`, `timeline`, `grid_view`).
- Indicador de selección y colores del `NavigationBar` ahora vienen del tema.
- Sin emojis (prueba automática que escanea todo `lib/`).

## FUNCIONALIDAD

No se tocó la lógica de negocio: pedidos, entregas, pagos, Yape, deudas,
balones, gastos, fallas, rendición, mapas y Realtime siguen igual.
Se actualizaron las expectativas de los tests de pestañas por los nuevos tabs.

## DATOS

Supabase/RLS/Outbox sin cambios. Pruebas reales: **23 PASS** (14 flujo + 9
casos A–F/duplicados/fondo), sin datos residuales.

## PRUEBAS

- `flutter analyze`: 0 errores, 0 warnings (94 infos de estilo).
- `flutter test`: **139 pruebas en verde**, incluidas 2 nuevas que validan la
  paleta del modo oscuro y claro.
- `flutter build apk --release --split-per-abi --target-platform android-arm64`: OK.
- APK **1.0.19+19**, `versionCode` 2019, `releases/app-v19.apk`.
  SHA-256: `D1B87BFE152FD4D1C1485205921AE35A15306BA152979F9AE04125116543092C`.

## PENDIENTE REAL

Verificación manual en teléfono del cambio de tema en pantallas específicas,
la animación del login y las transiciones. No hay dispositivo en este entorno.
No se declara terminado solo por compilar.
