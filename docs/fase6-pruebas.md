# FASE 6 — Pruebas obligatorias (27) y su resultado

Regla de este documento: **nada se marca como verificado en teléfono si solo se
probó en análisis estático o en el emulador**. Cada fila dice exactamente cómo
se comprobó.

Leyenda de la columna **Cómo**:

- **Auto**: prueba automática (`flutter test`) que se ejecuta en cada cambio.
- **BD real**: comprobación ejecutada contra el Supabase del proyecto.
- **Manual**: pendiente de probar en un teléfono real.

## Resultado global

| Fecha | `flutter analyze` | `flutter test` |
|---|---|---|
| 2026-11-15 | 0 errores · 0 advertencias (18 avisos de estilo preexistentes) | **99 pruebas en verde** |

Publicación OTA de esta versión: `releases/app-v8.apk` (arm64, 20.4 MB,
`version_code 2008`), descarga pública verificada por SHA-256 contra el APK
compilado. Detalle en `docs/fase6-informe-final.md`.

## Las 27 pruebas obligatorias

| # | Qué se comprueba | Cómo | Dónde |
|---|------------------|------|-------|
| 1 | El ADMIN inicia sesión y entra a su inicio | Manual (emulador) | — |
| 2 | El MOTORIZADO inicia sesión y entra a "Mis pedidos" | Manual (emulador) | — |
| 3 | El motorizado **no** puede abrir caja, rendición, conciliación, reportes, motorizados, cierre ni nuevo pedido | Auto / código | `main.dart` (`_rutasAdmin`), `navegacion_shell_test.dart` |
| 4 | El motorizado **sí** abre "Cobros" (antes rebotaba) | Auto / código | `main.dart`, `mas_page.dart` |
| 5 | El motorizado no entra al menú "Más" del admin ni el admin al del motorizado | Auto | `navegacion_shell_test.dart` |
| 6 | Ajustes se abre sin sesión (engranaje en bienvenida y login) | Auto | `ajustes_page_test.dart` |
| 7 | Ajustes no muestra claves ni credenciales | Auto | `ajustes_page_test.dart` |
| 8 | La barra inferior resalta la pestaña correcta, incluida una subpantalla | Auto | `navegacion_shell_test.dart` |
| 9 | Los estados del pedido respetan sus transiciones y no se saltan pasos | Auto | `estado_pedido_test.dart` |
| 10 | Un pedido cancelado/entregado no se reabre sin el admin | Auto + BD real (`reactivar_pedido`) | `estado_pedido_test.dart`, paso 4 |
| 11 | Solo lo **entregado** cuenta como venta (pendiente/cancelado/no entregado no suman) | Auto | `cierre_diario_test.dart` |
| 12 | Vendido ≠ cobrado: la deuda es la diferencia y nunca es negativa | Auto | `cierre_diario_test.dart`, `prioridad_y_deudas_test.dart` |
| 13 | Un cobro parcial deja deuda; el total deja PAGADO | Auto | `reglas_financieras_test.dart`, `entrega_sheet_test.dart` |
| 14 | "Quedó debiendo" no registra pago y deja la deuda completa | Auto | `entrega_sheet_test.dart` |
| 15 | Nunca se cobra más que el total del pedido | Auto | `entrega_sheet_test.dart` |
| 16 | Un cobro entra a la caja abierta **una sola vez** (idempotente) | BD real (paso 3 + `registrar_ingreso_caja`) | `supabase/steps/v7_03_trigger_pago.sql` |
| 17 | No se puede abrir dos cajas a la vez ni cerrar una cerrada | Auto / BD real | `caja_repo.dart`, paso 9 |
| 18 | Un gasto descuenta del bolsillo con el que se pagó (efectivo/Yape) | Auto | `cierre_diario_test.dart` |
| 19 | Los gastos guardan su medio de pago (con degradación si falta la migración) | Auto / BD real | `registro_gasto_page.dart`, paso 6 |
| 20 | La diferencia de rendición usa la fecha real de la rendición y descuenta gastos | Auto / código | `aprobacion_rendiciones_page.dart`, `cierre_diario_test.dart` |
| 21 | "Cancelar" en la aprobación **no** aprueba la rendición | Código (revisado) | `aprobacion_rendiciones_page.dart` |
| 22 | Una rendición aprobada no se puede modificar | Código / BD real | `rendiciones_repo.dart`, paso 9 |
| 23 | No se cierra la jornada con rendiciones pendientes | Código | `rendiciones_repo.dart` |
| 24 | Fierro y balón vacío son un solo activo retornable y **nunca se venden** | Auto | `reglas_financieras_test.dart`, `productos_repo.dart` |
| 25 | El saldo de fierros es entregados − devueltos y nunca negativo | Auto | `reglas_financieras_test.dart` |
| 26 | La ruta dibujada es la polilínea real de Google (no una línea recta) y sin clave se avisa con claridad | Auto (decodificación y gate) + **pendiente en teléfono** | `ruta_service_test.dart`, `ruta_page.dart` |
| 27 | La voz dice solo las indicaciones reales, en español, y calla si no hay ruta | Auto (texto/distancia) + **pendiente en teléfono** | `ruta_service_test.dart`, `voz_service.dart` |

## Pruebas adicionales ya en verde

- Multiempresa: el admin de una empresa no ve ni escribe datos de otra
  (`flujo_pedidos_test.dart`, se ejecuta contra la BD real cuando se pasan las
  credenciales por `--dart-define`).
- Entrega duplicada del mismo pedido rechazada.
- Balón vacío: por defecto queda pendiente; si el cliente lo devuelve, se registra.
- Prioridad por antigüedad y orden de la lista de pedidos.
- Formato de dinero, fechas y horas en español.
- Navegación y pestañas por rol.

## Lo que **todavía** requiere un teléfono real

Estas cosas no se pueden afirmar desde el análisis estático:

1. **Google Maps dentro de la app**: hace falta una clave válida con *Maps SDK
   for Android* y *Directions API* habilitadas (ver `docs/fase6-mapa-y-voz.md`).
   Sin clave, la app muestra el mapa alternativo con el aviso, que es el camino
   ya probado de forma automática.
2. **Asistente de voz**: depende del motor de voz en español instalado en el
   teléfono. La app lo detecta y avisa si no existe.
3. **Sincronización en segundo plano** con la app cerrada: depende de las
   restricciones de batería de cada marca; se probó el arranque y el ciclo de
   vida en emulador, no en un teléfono real.
4. **Instalación del APK y actualización OTA** en un dispositivo físico.

## Cómo reproducir

```powershell
cd app
flutter analyze
flutter test
```

Para la integración real (opcional):

```powershell
flutter test test/integration `
  --dart-define=TEST_SUPABASE_URL=https://kzhvutzkggcgrnalpcqs.supabase.co `
  --dart-define=TEST_SUPABASE_ANON_KEY=... `
  --dart-define=TEST_ADMIN_EMAIL=admin@grupojck.app `
  --dart-define=TEST_ADMIN_PASSWORD=admin123 `
  --dart-define=TEST_MOTO_EMAIL=999888777@grupojck.app `
  --dart-define=TEST_MOTO_PASSWORD=demo123
```
