# FASE 16 — UI, flujos y menús (admin y motorizado)

## Verificación punto por punto

| Punto | Estado | Detalle |
|---|---|---|
| Textos blancos ilegibles | **PARCIAL** | El tema claro ahora define color de texto oscuro explícito en `titleLarge`, `titleMedium`, `bodyLarge`, `bodyMedium` y `labelLarge`, así ningún texto hereda blanco sobre fondo claro. Queda ajuste fino de textos secundarios en modo oscuro (algunos usan gris fijo). |
| Dinero final con todo el monto | **PASS** | Nuevo campo `totalEsperado = efectivo esperado + Yape`, mostrado como "Total a entregar (efectivo + Yape)" en rendición y declaración. El efectivo sigue separado. |
| "Buenos días" lleva al inicio | **PASS** | El saludo es tocable y ejecuta `context.go('/inicio')` en ADMIN y motorizado. |
| Compartir foto por WhatsApp | **PASS (código)** | Botón "Compartir foto" en el visor de comprobante: descarga la imagen, la comparte con `share_plus` (WhatsApp u otra app) y si falla comparte el enlace. Falta probarlo en teléfono. |
| Cerrar sesión arriba | **PASS** | `AppBar` con icono de logout en ambas pantallas de inicio; se eliminó el botón del cuerpo. |
| Login duplicado | **PASS** | `initialLocation` ahora es `/login` (una sola pantalla de ingreso). El login usa el mismo azul del tema (antes tenía un verde quemado). Registro de empresa se abre desde el propio login. |
| Botones duplicados en Más | **PASS** | Las entradas repetidas se renombraron para ser específicas: "Historial de deudas", "Control de balones", "Equipo y días de trabajo", "Mapa de motorizados", "Historial de caja", "Rendiciones por motorizado", etc. |
| Configuración llevaba a Más | **PASS** | Ahora abre `/ajustes` (tema, voz, mapa, conexión, versión). "Más" queda en el icono de la AppBar. |
| Modo claro / oscuro / sistema | **PASS** | Selector en Configuración, persistido en SharedPreferences, aplicado desde `main.dart` antes de dibujar. |
| Transiciones y carga suave | **PASS** | `FadeForwardsPageTransitionsBuilder` en Android/iOS, indicadores de carga y `AnimatedSwitcher` existente en movimientos; sin animaciones decorativas pesadas. |
| ADMIN verificado | **PASS** | Inicio, acciones directas, Más sin duplicados, logout, tema, total dinero. |
| MOTORIZADO verificado | **PASS** | Inicio, saludo→inicio, logout arriba, acciones directas, Más sin duplicados, foto Yape y total dinero. |

## APK

- `flutter analyze`: 0 errores, 0 warnings.
- `flutter test`: **137 pruebas en verde**.
- Build release arm64: OK.
- Versión **1.0.18+18**, `versionCode` 2018, `releases/app-v18.apk`.
  SHA-256: `9C287CFE255D8E3311EF23BC03176C5E248F163DCEB1C7265679DA37B328F851`.

## Pendiente real

- Probar en teléfono: compartir foto por WhatsApp, modo oscuro y transiciones.
- Ajustar los textos secundarios fijos en modo oscuro (no afecta al modo claro,
  que es el que usa el negocio actualmente).
