# FASE 11 — Simplificación y corrección integral del flujo

## 1. Problemas encontrados

Auditoría real del código y de la base en vivo (login MOTORIZADO
`999888777@grupojck.app`):

| Síntoma | Origen confirmado |
|---|---|
| "No se pudo registrar / No está autorizado" al registrar gasto | `42501 new row violates row-level security policy for table "gastos"` (HTTP 403) |
| "No autorizado" al crear pedido desde el motorizado | `42501 new row violates row-level security policy for table "pedidos"` (HTTP 403) |
| La foto de Yape no se guardaba en la entrega normal | `pagos.comprobante_url` no existía (`42703`); la hoja de entrega no pedía foto |
| Los gastos no aparecían en "Mi registro" | `gastos` solo tenía política INSERT para ADMIN |
| Admin no veía cobros/gastos sin recargar | `pagos` y `gastos` no estaban en la publicación Realtime |
| GPS "en vivo" con datos viejos | Faltaba confianza en la frescura; se ha reforzado en todas las vistas |
| Rendición con solo fondo o solo gastos aparecía vacía | `Rendicion.vacio` solo miraba pedidos |
| La declaración precargaba solo el efectivo cobrado | No sumaba fondo ni descontaba gastos en efectivo |
| `fondo_vuelto` no existía | `PGRST205`: tabla ausente en el esquema en vivo |
| `productos.tipo`, `perfiles.dias_trabajo` ausentes | `42703`: migraciones 10–13 no aplicadas |
| Pedido entregado podía quedar con estado viejo | Faltaba reconciliación/unificación de la publicación Realtime |
| Calendario: aviso de "no suele trabajar hoy" no se mostraba al asignar | La lógica existía en `motorizadosRepo` pero no se usaba en la asignación |

No se creó ningún sistema paralelo: se reutilizaron `pedidos`, `entregas`,
`pagos`, `movimiento_bal_on`, `movimiento_fierro`, `gastos`, `rendiciones`,
`cierre_diario`, `ubicaciones_motorizado`, el `Outbox` y el `SyncBus`.

## 2. Causa del "No autorizado"

La cadena real era:

```
Flutter → AuthNotifier (rol MOTORIZADO, empresa e4422e42-…)
        → pedidosRepo / gastoRepository
        → PostgREST INSERT
        → RLS: política "pedidos_insert" / "gastos_admin" (solo es_admin())
        → 42501 → traducido como "no tienes permiso"
```

`auth.uid()` y `mi_empresa()` funcionaban correctamente (perfil verificado:
`rol=MOTORIZADO`, `empresa_id=e4422e42-824f-4cb2-88c8-abe8f028331d`).
El rechazo estaba **únicamente en las políticas RLS**: las migraciones
`v7_11` y `v7_14` (que crean `pedidos_moto_insert`, `detalle_moto_insert`,
`gastos_moto_insert`, `clientes_moto_insert`, etc.) no estaban aplicadas en la
base de producción.

## 3. Corrección de permisos/RLS

Nuevo paso **`v7_15_flujo_simple.sql`**, autónomo y reejecutable:

- Repone **todas** las políticas del motorizado: clientes (insert/update),
  pedidos (insert `origen='MOTORIZADO'`, update del asignado), detalle,
  gastos, incidencias, entregas, pagos, movimientos de balón/fierro,
  rendiciones y ubicaciones.
- El motorizado **solo** puede insertar filas con `empresa_id = mi_empresa()` y
  su propio `auth.uid()` (`creado_por`, `usuario_id`, `motorizado_id`,
  `repartidor_id`, `registrado_por`).
- No puede modificar movimientos ajenos ni configuración administrativa: caja, cierre
  diario, fondo de vuelto y configuración siguen siendo solo ADMIN.
- No se desactivó RLS en ninguna tabla.

La app ya no dice simplemente "No autorizado": `sb.dart` traduce `42501`,
`42703`, `42P01` y `PGRST205` a un aviso que indica ejecutar el paso 15 en
Supabase → SQL Editor.

## 4. Cambios realizados

- Un único flujo: ADMIN crea pedido → asigna (ADMIN o motorizado) →
  motorizado lo recibe → GPS → entrega → pago (efectivo/Yape/deuda) →
  balón → gasto → rendición → caja.
- `precio_base` sigue siendo sugerencia; `total`/`precio_unitario` capturan el
  precio libre real (libre, sin límites artificiales).
- Pantallas simplificadas a 6 accesos admin y 4 accesos motorizado.
- Pedidos de hoy por defecto, con hora, cliente, monto, motorizado y estado.
- Seguimiento con pedido activo, distancia/ETA reales y botón "Ver ruta".
- Foto de Yape en la entrega normal + persistencia offline.
- Fondo de vuelto, efectivo esperado, declarado y diferencia en todas las
  vistas de rendición.
- Aviso no bloqueante al asignar a un motorizado que no suele trabajar hoy.

## 5. Tablas modificadas

`pedidos`, `detalle_pedido`, `clientes`, `gastos`, `pagos`, `entregas`,
`movimiento_bal_on`, `movimiento_fierro`, `productos`, `perfiles`,
`rendiciones`, `cierre_diario`, `incidencias`, `ubicaciones_motorizado`.

**Nueva:** `public.fondo_vuelto`
(`id, empresa_id, motorizado_id, monto, fecha, entregado_por, observaciones, uuid_offline`).

## 6. Migraciones creadas

- `supabase/steps/v7_15_flujo_simple.sql` — paso 15 (autónomo, reejecutable,
  no destructivo; incluye verificación final con `true` en todo).
- `supabase/steps/00_LEEME.md` — paso 15 documentado como obligatorio.
- `supabase/steps/99_verificar.sql` — nuevas comprobaciones de fondo,
  columnas y Realtime.

## 7. Repositories modificados

`sb.dart`, `pedidos_repo.dart`, `entregas_repo.dart`, `rendicion_repo.dart`,
`rendiciones_repo.dart`, `pagos_repo.dart` (sin cambios de lógica),
`outbox.dart`.

**Nuevo:** `fondo_vuelto_repo.dart`.

## 8. Servicios modificados

`comprobante_service.dart` (reutilizado), `ruta_service.dart` (reutilizado),
`ubicacion_service.dart` (reutilizado), `SyncBus`/`SyncService` (sin cambios;
ahora todos los repositorios avisan), `ComprobanteService.subir` vía
`flujo_entrega` y `Outbox`.

## 9. Pantallas modificadas

`home_page.dart`, `home_moto_page.dart`, `pedidos_page.dart`,
`pedido_detalle_page.dart`, `entrega_sheet.dart`, `flujo_entrega.dart`,
`mi_registro_page.dart`, `rendicion_page.dart`,
`declarar_rendicion_page.dart`, `motorizados_actividad_page.dart`,
`seguimiento_page.dart`, `mapa_selector_page.dart`.

## 10. Google Maps integrado

- `RutaPage`: GoogleMap nativo + Directions reales (polylínea, distancia,
  duración, indicaciones y voz) cuando hay `GOOGLE_MAPS_API_KEY`; OSM como
  respaldo sin clave.
- `SeguimientoPage`: GoogleMap nativo con marcadores de todos los motorizados
  y polylínea de la ruta calculada; OSM como respaldo.
- `MapaSelectorPage`: GoogleMap nativo para colocar/mover el pin, conservando
  exactamente la búsqueda, ubicación actual y campos de dirección/referencia.
- La clave **no** está en el código: se pasa por `--dart-define` y/o
  `android/local.properties` (`maps.apiKey`), archivos ignorados por git.

## 11. GPS integrado

- `UbicacionService` sigue enviando cada 30 s solo con jornada/pedido activo.
- Admin ve frescura honesta: "hace 8 s", "hace 3 min", "sin actualizar"; el
  color del marcador cambia y nunca se muestra "en vivo" con dato viejo.
- RLS impide que el motorizado A modifique la ubicación del B
  (`usuario_id = auth.uid()`).

## 12. Realtime integrado

Publicadas y escuchadas: `pedidos`, `pagos`, `gastos`, `entregas`,
`incidencias`, `ubicaciones_motorizado`, `rendiciones` y `fondo_vuelto`.
Ninguna pantalla necesita recargar manualmente: Realtime + `SyncBus` +
`Outbox.procesar()` avisan a Admin y motorizado.

## 13. Rendición implementada

Automática, sin volver a registrar pedidos:

```
fondo inicial + efectivo cobrado − gastos pagados en efectivo = efectivo esperado
diferencia = efectivo declarado − efectivo esperado
```

Separación estricta: Efectivo / Yape / Deuda. La deuda no cuenta como efectivo.
Cierre inmutable: una rendición `APROBADA` no se puede modificar; las
correcciones pasan por `REVISAR:<estado>` y quedan en `auditoria`.

## 14. Fondo inicial implementado

Tabla `fondo_vuelto` + botón "Fondo" en Rendiciones (ADMIN elige motorizado,
monto y observación). No es venta ni ingreso. Aparece en Mi registro, detalle
del motorizado, declaración y rendición del admin.

## 15. Gastos implementados

El motorizado registra gasto con categoría, monto, medio de pago y
descripción; entra solo a su empresa y es visible de inmediato para ADMIN.
En la rendición solo descuentan del efectivo los gastos pagados en efectivo.

## 16. Seguridad implementada

RLS por empresa + rol + dueño de la fila; sin RLS desactivado. Idempotencia por
`uuid_offline` en pedidos, entregas, pagos, gastos, incidencias y fondos.
La doble entrega está impedida por `entregas.pedido_id UNIQUE` y por
`estado_pago`/auditoría.

## 17. Pruebas realizadas

- Verificación REST real con el usuario motorizado: confirmados los `42501`
  originales y las columnas/tablas ausentes.
- `flutter analyze`: **0 errores, 0 warnings** (26 infos de estilo).
- `flutter test`: **129 pruebas en verde** (114 anteriores + 15 nuevas de
  rendición, errores de migración y foto Yape).
- Pruebas unitarias nuevas: fondo + efectivo − gastos, diferencia ±, jornada
  con solo fondo/gasto no vacía, mensajes 42501/42703/PGRST205, foto en Yape.

## 18. flutter analyze

`flutter analyze --no-pub` → 0 errores, 0 warnings.

## 19. flutter test

`flutter test --no-pub` → `All tests passed!` (129).

## 20. Resultado de prueba end-to-end

**Parcialmente ejecutada y bloqueada por un paso externo.**

- Ejecutado y verificado: login ADMIN y MOTORIZADO, lectura de pedidos/clientes,
  detección real del `42501` en `gastos` y `pedidos`, ausencia real de
  `pagos.comprobante_url`, `productos.tipo`, `perfiles.dias_trabajo` y
  `fondo_vuelto`, y falta de publicación Realtime de `pagos`/`gastos`.
- No se pudo completar el recorrido `ADMIN → PEDIDO → MOTORIZADO → GPS →
  ENTREGA → YAPE → GASTO → RENDICIÓN → CAJA` contra la base porque el paso 15
  todavía **no está aplicado**: no hay token de Management API, password de DB,
  CLI de Supabase ni `psql` en este entorno, y DDL no se puede ejecutar con la
  service key por REST.
- Lo que sí quedó demostrado: la corrección está implementada en código y en
  SQL; en cuanto se ejecute el paso 15, las mismas operaciones que hoy devuelven
  `42501`/`42703`/`PGRST205` pasan a estar permitidas y visibles en Realtime.
- APK compilado y publicado: **1.0.14+14**, `versionCode` real **2014**,
  `releases/app-v14.apk`, `app_versiones.version_code=2014`.
  SHA-256: `1255C24AE6A866D0F411711C2852BECFCBFFB425043CD9666E8DE21B4D78C437`.

## 21. Problemas pendientes (reales)

1. **Aplicar el paso 15 en Supabase Dashboard → SQL Editor** y luego ejecutar
   `99_verificar.sql` (todo debe salir `OK`). Sin esto el motorizado seguirá
   recibiendo "No autorizado" en producción, aunque la app ya explica la causa.
2. Repetir la prueba end-to-end en teléfono real tras aplicar la migración,
   especialmente la subida de la foto de Yape a Storage y el flujo offline.
3. Configurar `GOOGLE_MAPS_API_KEY` real (Directions + Maps SDK para Android)
   por `--dart-define`/`local.properties`; sin clave se usa OSM y no hay ETA.
4. No hay clave de Google Maps ni dispositivo físico en este entorno, por lo
   que GPS en campo y TTS no se pudieron verificar en vivo.
