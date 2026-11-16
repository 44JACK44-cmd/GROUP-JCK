# FASE 10 — Informe final: sincronización total, Mi registro y seguimiento GPS

Fecha: 2026-11-16
Versión: **1.0.13+13** (versionCode real del APK: **2013**)

## 1. Objetivo

Que cada acción (asignar, entregar, cobrar, gastar, registrar pedido propio)
se refleje **de inmediato y sin volver a entrar** en todas las pantallas, y que
el administrador vea la actividad y la ubicación reales del motorizado sin
datos falsos ni estados viejos.

## 2. Causas raíz encontradas y corregidas

| Síntoma | Causa real | Corrección |
|---|---|---|
| `GoException: no routes for location: historial` | La ruta `/historial` no estaba registrada en `main.dart` | Registrada dentro del shell del motorizado |
| Entregado seguía apareciendo pendiente | Se actualizaba `pedidos.estado` sin comprobar que la fila cambió; estados viejos con `entregas` ya creadas | `entregas_repo` verifica el estado final leyendo la base; migración 14 reconcilia |
| Acciones no se veían hasta reentrar | Solo `pedidos` estaba en Realtime y nadie avisaba a las pantallas tras un guardado | `SyncBus` + realtime de `pagos`, `gastos`, `entregas` e `ubicaciones_motorizado` |
| Gastos del motorizado no aparecían | RLS de `gastos` era solo ADMIN (insert/select fallaban con 42501) | Políticas `gastos_select` / `gastos_moto_insert` (paso 14) |
| Foto de Yape se perdía en modo offline | `pedido_completo` guardaba `comprobante_local_path` dentro del mapa del pago → PostgREST rechazaba la fila entera | El Outbox limpia la clave, sube la foto y reintenta el pago sin `comprobante_url` si la migración falta |
| Lista "parpadeaba" con datos viejos | Cargas solapadas sin control de petición | Guardas `_peticion` en historial, Mi registro, detalle de motorizado y seguimiento |
| "EN LÍNEA" con GPS viejo | No existía frescura ni tabla de ubicación | `ubicaciones_motorizado` + estados honestos (en vivo / hace poco / sin actualizar) |

## 3. Cambios funcionales

### Sincronización
- `SyncBus` (`core/state/bus.dart`): avisos de pedidos, dinero y ubicaciones.
  Se emiten **después de confirmar** cada escritura y tras sincronizar el
  Outbox. Las pantallas escuchan y recargan solas.
- Escrituras verificadas en `pedidos_repo`, `entregas_repo`, `pagos_repo`,
  `balones_repo`, `caja_repo`, gastos e incidencias.

### Motorizado
- Pestañas: **Inicio · Mis pedidos · Mi registro · Historial · Más**.
- **Mi registro** es la bitácora real (resumen de `rendicionRepo` + movimientos
  de `actividadRepo`): pedidos, gastos, incidencias y foto de Yape, con
  navegación por día.
- Botones grandes para registrar pedido, gasto o falla; todo entra también sin
  conexión (cola con `uuid_offline`).
- Tarjeta de GPS: activa / pausada / sin permiso / último envío.

### Administrador
- Inicio con bloque **"Actividad en vivo"** por motorizado (última actividad,
  pedidos, ventas y frescura de ubicación) + acceso a **Seguimiento GPS**.
- Detalle por motorizado con el mismo resumen y las mismas filas
  (`ActividadTile`) que ve el motorizado: información consistente.
- `SeguimientoPage`: mapa OpenStreetMap con marcadores coloreados por frescura
  y lista honesta ("Sin ubicación compartida" cuando no hay dato).

### GPS
- Tabla `ubicaciones_motorizado` (una fila por usuario), RLS por empresa y
  escritura solo del propio usuario.
- Envío cada **30 s** y con movimiento mínimo de **25 m**, solo durante el
  trabajo; se detiene y borra la fila al cerrar sesión.

## 4. Base de datos (paso 14 — pendiente de aplicar)

Archivo: `supabase/steps/v7_14_sincronizacion.sql` (reejecutable, no
destructivo). Crea/ajusta:
1. `ubicaciones_motorizado` + políticas + índice.
2. `gastos.uuid_offline` + políticas del motorizado.
3. Políticas del cuaderno del motorizado (pedido/cliente propios).
4. Columnas aditivas: `pagos.comprobante_url`, bucket `comprobantes`,
   `productos.tipo`, `perfiles.dias_trabajo`.
5. Publicación Realtime: `pedidos`, `pagos`, `gastos`, `entregas`,
   `incidencias`, `ubicaciones_motorizado`.
6. Reconciliación: pedido con `entregas` real pero estado viejo → `ENTREGADO`
   (no toca cancelados).

Deben aplicarse los pasos **10 a 14** en orden y luego `99_verificar.sql`.
La app tiene respaldos en tiempo de ejecución, pero las fotos de Yape, los
gastos del motorizado, el GPS y el tiempo real quedan completos recién con la
migración aplicada.

## 5. Pruebas

- `flutter analyze`: **0 errores, 0 advertencias** (24 avisos de estilo
  preexistentes).
- `flutter test`: **114 pruebas en verde** (se suman las de sincronización y
  navegación con "Mi registro").
- Verificado en base real que `pagos`/`gastos` no avisaban por Realtime y que
  faltaban las columnas/tablas; por eso el paso 14.

## 6. APK publicado

- Versión: **1.0.13+13**, `versionCode` real **2013** (arm64 suma 2000).
- `flutter build apk --release --split-per-abi --target-platform android-arm64`
  (22 079 957 bytes).
- Publicado como `releases/app-v13.apk`; `app_versiones` en `version_code 2013`.
- SHA-256 verificado byte por byte tras descargar la URL pública:
  `C22548B55D29534F284BFB84E401D766033B0C02B1443C69733E80B6AC9674A9`.

## 7. Pendiente de probar en teléfono real

1. Permiso de ubicación en Android 12+ y envío efectivo cada 30 s.
2. Instalación del APK y actualización OTA.
3. Flujo completo recepción → motorizado → cobro Yape → rendición → Mi registro,
   con el teléfono en modo avión para validar la cola offline.
