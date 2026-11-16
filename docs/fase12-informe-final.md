# FASE 12 — Rediseño, Realtime único y Google Maps en el flujo principal

## Estado previo (inspección)

Ya existían y se conservaron: Supabase multiempresa, RLS, Auth, `Outbox`/
`SyncService`, repositorios por dominio, `ActividadRepo`, `RutaService`,
`EstadoPedido`, `RutaPage` con Google Maps, selector de ubicación y el tema
suave de `app/theme.dart`. **No se rehízo el proyecto**: se reorganizó la
capa reactiva y la capa visual.

## 1. Archivos modificados

**Nuevos**

- `core/realtime/realtime_service.dart`
- `core/ui/diseno.dart`
- `core/ui/estado_conexion.dart`
- `core/ui/aviso_maps.dart`
- `core/ui/estado_stepper.dart`
- `features/movimientos/movimientos_page.dart`
- `core/data/fondo_vuelto_repo.dart` (fase anterior)
- `supabase/steps/v7_16_comprobantes_gasto_falla.sql`
- `test/unit/diseno_y_realtime_test.dart`

**Modificados**

`main.dart`, `app/theme.dart`, `core/state/bus.dart`,
`core/offline/sync_service.dart`, `core/offline/outbox.dart`,
`core/data/actividad_repo.dart`, `core/data/rendicion_repo.dart`,
`features/home/home_page.dart`, `features/home/home_moto_page.dart`,
`features/pedidos/pedidos_page.dart`, `features/pedidos/mis_pedidos_page.dart`,
`features/pedidos/historial_page.dart`, `features/pedidos/entrega_sheet.dart`,
`features/pedidos/nuevo_pedido_page.dart`, `features/pedidos/pedido_detalle_page.dart`,
`features/mi_registro/registro_pedido_page.dart`,
`features/mi_registro/registro_gasto_page.dart`,
`features/mi_registro/registro_incidencia_page.dart`,
`features/mi_registro/mi_registro_page.dart`,
`features/motorizados/motorizados_actividad_page.dart`,
`features/seguimiento/seguimiento_page.dart`,
`features/rendicion/rendicion_page.dart`,
`features/rendicion/declarar_rendicion_page.dart`,
`features/clientes/mapa_selector_page.dart`, `features/rutas/ruta_page.dart`,
`features/ajustes/ajustes_page.dart`, `features/deudas/deudas_page.dart`,
`features/finanzas/cobros_page.dart`, `features/pagos/pago_sheet.dart`,
`features/rendicion/conciliacion_page.dart`, `features/motorizados/motorizados_page.dart`,
`pubspec.yaml`, tests y documentación de migraciones.

## 2. Funcionalidades agregadas

- Sección **Movimientos** (timeline real de pedidos, pagos, gastos, fallas).
- Stepper visual del estado del pedido, sin saltos inválidos (la autoridad
  sigue siendo `EstadoPedido` + RLS).
- **Ir al cliente** abre Google Maps con las coordenadas **del cliente**.
- Foto opcional del comprobante en **gastos** y **fallas**, con subida a
  Supabase Storage y persistencia offline.
- La hora del pedido la pone la base (`pedidos.fecha default now()`); se
  eliminó el selector manual de hora en el cuaderno del motorizado.
- Rendición con pedidos registrados por motorizado, fallas y su costo.
- Indicador de conexión y sincronización en tiempo real.

## 3. Problemas de actualización corregidos

Antes: cada pantalla creaba su propio canal Realtime (había 8 canales
independientes), se duplicaban consultas, no se cancelaban al navegar y el
estado local quedaba viejo si Realtime no avisaba.

Ahora:

1. **Un solo canal global** (`RealtimeService`) suscrito a 14 tablas.
2. Cada cambio traduce a `SyncBus` (pedidos, dinero, ubicaciones, movimientos,
   rendiciones).
3. Las pantallas solo escuchan `SyncBus` y vuelven a leer la base; se
   desuscriben en `dispose` → sin fugas.
4. Las escrituras propias avisan por el bus aunque Realtime falle.
5. Al volver Internet, `SyncService` re-suscribe el canal y vacía el Outbox.

## 4. Cómo funciona Realtime

```
Supabase (14 tablas publicadas)
        │  un único RealtimeChannel
        ▼
RealtimeService._avisar(tabla)
        ▼
SyncBus (ValueNotifier)
        ▼
initState/addListener → _cargar() → estado real de la UI
```

No hay botones "Actualizar" como solución principal; el pull-to-refresh queda
solo como gesto complementario.

## 5. Google Maps

- `google_maps_flutter` es el mapa principal en `RutaPage`, `SeguimientoPage` y
  `MapaSelectorPage`; OSM queda como respaldo honesto.
- La clave se inyecta desde `android/local.properties` (`maps.apiKey`) o
  `GOOGLE_MAPS_API_KEY`; el manifest usa `${mapsApiKey}` y **no contiene claves**.
- Permisos de ubicación y `meta-data` de la API ya están en el manifest.
- `AvisoGoogleMaps` dice explícitamente cuando la compilación no tiene clave.
- **Pendiente real:** esta compilación no lleva clave válida; hay que generarla
  con `--dart-define`/`local.properties` y probarla en teléfono.

## 6. Registro manual del motorizado

"Mi registro" sigue permitiendo pedido, gasto y falla. El pedido se crea con
`origen='MOTORIZADO'` y `creado_por=auth.uid()`, aparece como "Registrado por
motorizado" en Movimientos/rendición y es visible para ADMIN por Realtime.
Idempotencia por `uuid_offline`; no se duplica al reintentar.

## 7. Gastos y fallas

Categorías con iconos Material, monto, medio de pago, descripción y foto
opcional. Si no hay red, la ruta local se guarda en el Outbox y se sube al
sincronizar. La columna `comprobante_url` la crea el paso 16.

## 8. Rendición

Automática, sin reescribir datos: fondo + efectivo − gastos en efectivo =
esperado; diferencia = declarado − esperado. Yape y deuda van separados.
Incluye pedidos manuales, fallas, balones y fondo. ADMIN revisa con
Aprobar/Observar y la diferencia se muestra con texto.

## 9. Pruebas ejecutadas

- `flutter analyze --no-pub`: **0 errores, 0 warnings** (29 infos de estilo).
- `flutter test --no-pub`: **133 pruebas en verde**.
- Nueva prueba que recorre todos los `.dart` de `lib` y falla si aparece
  cualquier emoji (U+2600–U+27BF, U+1F000–U+1FAFF, U+FE0F).

## 10. Resultado `flutter analyze`

0 errores, 0 warnings.

## 11. Resultado `flutter test`

`All tests passed!` — 133 pruebas.

## 12. Resultado del build

`flutter build apk --release --split-per-abi --target-platform android-arm64`
→ OK. Versión **1.0.15+15**, `versionCode` real **2015**.
Publicado en `releases/app-v15.apk` y `app_versiones.version_code=2015`.
SHA-256:
`DD9A31A030DD973539D71A61055CFE4FB7C43A7853D8DB005F933ACE1707EAF0`.

## 13. Problemas pendientes (reales)

1. Aplicar en Supabase los pasos **15** y **16** del SQL Editor. Sin el paso 15
   las tablas nuevas no están publicadas en Realtime y el motorizado sigue con
   RLS restringida; sin el 16 no se guardan fotos de gasto/falla.
2. Configurar una `GOOGLE_MAPS_API_KEY` válida y validar navegación/ETA en un
   teléfono real (no hay dispositivo ni clave en este entorno).
3. La prueba end-to-end completa contra producción sigue sujeta a los dos
   puntos anteriores. No se declara terminada solo porque compile: lo que sí
   queda verificado es la estructura reactiva, la ausencia de emojis, la
   lógica financiera y la compilación.
