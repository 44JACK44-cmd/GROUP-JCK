# FASE 6 — Informe final

Fecha: 2026-11-15
Versión: **1.0.8+8**
Commit base de esta etapa: `0c410f9`

## 1. Objetivo y reglas de la fase

Auditar y corregir la app completa (Flutter + Supabase) para que sirva en el
trabajo real de reparto de gas, sin rehacer la arquitectura y sin perder nada de
lo que ya funcionaba.

Reglas que se respetaron en todo momento:

- No se reescribió la app ni se cambió la arquitectura (Flutter, Supabase,
  cola offline).
- No se borró ninguna función que ya funcionaba.
- Las migraciones son **no destructivas y reejecutables**; se aplican a mano en
  el SQL Editor de Supabase.
- Nunca se afirma que algo funciona en teléfono si solo se probó con análisis
  estático o emulador.

## 2. Qué se corrigió, por etapa

### ETAPA A — Diagnóstico
`docs/fase6-etapa-a-diagnostico.md`: inventario de fallos P0–P3 con evidencia y
pruebas contra la base real.

### ETAPA B — Flujo de pedidos, dinero y permisos
- Asignar, tomar, liberar y reactivar pedidos con RPC y verificación de filas.
- "No entregado" cambia el estado y deja auditoría, **sin** crear una entrega
  falsa ni dinero.
- Acciones del detalle según el rol del usuario.
- Cada cobro entra a la caja abierta **una sola vez** (trigger + RPC idempotente
  + red de seguridad en la app).
- Caja: no se puede abrir dos veces ni cerrar una cerrada; el resumen se limita
  a esa caja y a su ventana de tiempo.
- Gastos con `medio_pago`: descuentan del bolsillo correcto.
- Rendición aprobada = inmutable.
- Sincronización automática (conexión, ciclo de vida y temporizador) integrada
  en `main.dart`, con sección propia en Ajustes.
- Fierro y balón vacío: **un solo concepto comercial** `RETORNABLE`, precio 0,
  nunca se vende; se controla por saldo (entregado − devuelto, nunca negativo).

### ETAPA C — Mapa y voz
- `google_maps_flutter` para el mapa dentro de la app y **Directions** para la
  ruta real (polilínea, no una línea recta).
- `flutter_tts` en español (`es-PE`, respaldo `es-ES`) que lee **solo** las
  indicaciones reales de la ruta.
- Si no hay clave de Google Maps: mapa alternativo (OpenStreetMap), aviso claro
  y botón para abrir Google Maps. Nada de rutas inventadas.
- La clave nunca se sube al repositorio: se inyecta al compilar desde
  `android/local.properties` (`maps.apiKey`) o la variable de entorno.
- Documento de configuración: `docs/fase6-mapa-y-voz.md`.

### ETAPA D — Experiencia real
- El motorizado ya **no** rebota al tocar "Cobros"; sigue sin acceso a caja,
  rendición, conciliación, reportes, motorizados, cierre y nuevo pedido.
- La barra inferior resalta la pestaña correcta, incluso en subpantallas.
- Inicio del admin sin accesos duplicados: ahora lleva a Caja, Rendición,
  Reportes, Motorizados y Conciliación.
- Refresco real (tirar hacia abajo) en caja, rendición, cierre y conciliación.
- Se acabaron los "errores técnicos" en pantalla: los mensajes se traducen y
  los fallos de red ya no expulsan al usuario de su sesión.
- La observación del gasto ya no se pierde.
- "Cancelar" al revisar una rendición ya no la aprueba.
- No se puede cerrar la jornada con rendiciones pendientes.

### ETAPA E — Sincronización
`SyncService` reintenta la cola pendiente al recuperar conexión, al volver a la
app y cada 60 segundos, sin gastar batería si no hay red.

### ETAPA F — Pruebas
- **99 pruebas automáticas en verde**; `flutter analyze` sin errores ni
  advertencias (solo 18 avisos de estilo preexistentes).
- Las 27 pruebas obligatorias y su estado exacto están en
  `docs/fase6-pruebas.md`, distinguiendo lo probado automáticamente, lo
  verificado contra la base real y lo que falta en un teléfono.

### ETAPA G — APK
- Versión subida a **1.0.8+8**.
- `flutter build apk --release` correcto:
  `app/build/app/outputs/flutter-apk/app-release.apk` (58.6 MB).
- Aviso honesto: el APK se firma con la clave de depuración porque el proyecto
  todavía no tiene un keystore de producción configurado. Sirve para instalar
  y probar, **no** para publicar en Play Store.

## 3. Base de datos — estado

Migraciones por pasos en `supabase/steps/`, reejecutables y sin borrar datos:

1. checks (`DEUDA`, `NO_ENTREGADO`, `PARCIAL`)
2. trigger de entrega
3. trigger de pago + `registrar_ingreso_caja`
4. guard de reapertura + `reactivar_pedido`
5. `pedidos.origen` + `incidencias`
6. `gastos.medio_pago` + `rendiciones` + `cierre_diario`
7. zonas + `asignar_por_zona` + `tomar_pedido` + `liberar_pedido`
8. solo el motorizado asignado (o admin) registra entrega/cobro
9. índices únicos (caja abierta, cobro idempotente, rendición diaria)
10. `productos.tipo`, depuración de duplicados sin borrar y "Fierro / Balón
    vacío" como único activo retornable
11. **nuevo**: el motorizado puede registrar su propio pedido y cliente
    (origen `MOTORIZADO`), y nada más

### Pendiente de aplicar por el usuario

Los pasos **10 y 11** todavía no están en la base real. Hasta aplicarlos la app
funciona igual, pero:

- el catálogo seguirá mostrando balones duplicados;
- el motorizado no podrá registrar pedidos desde su teléfono (verá un aviso
  claro en vez de un error técnico).

Orden: abrir `supabase/steps/00_LEEME.md`, ejecutar los archivos en orden en el
SQL Editor y al final `99_verificar.sql` (todo debe salir en `OK`).

## 4. Lo que NO está verificado en un teléfono real

1. Mapa de Google dentro de la app (necesita clave válida y un teléfono).
2. Asistente de voz (depende del motor de voz del teléfono).
3. Sincronización en segundo plano con la app cerrada (restricciones de batería
   de cada marca).
4. Instalación del APK y actualización OTA en un dispositivo físico.

El resto del flujo (pedidos, entregas, cobros, caja, rendición, cierre, roles,
aislamiento multiempresa) se probó con pruebas automáticas y contra la base real
según el detalle de `docs/fase6-pruebas.md`.

## 5. Publicación OTA — hecha

| Dato | Valor |
|---|---|
| Fecha | 2026-11-15 |
| Archivo subido | `releases/app-v8.apk` |
| Tamaño | 21 405 496 bytes (20.4 MB) |
| SHA-256 | `22A5DF41D3FBEE290E37D5E0B693DC3DD047143C8AB73B5407CBCACDF4BA1D45` |
| `app_versiones` | `version_code 2008`, `version_name 1.0.8`, `obligatoria false` |

Comprobaciones hechas antes y después de publicar:

- El APK subido se descargó de la URL pública y su SHA-256 coincide **byte por
  byte** con el compilado en local.
- `aapt dump badging`: `com.grupojck.gas_app`, `versionCode='2008'`,
  `versionName='1.0.8'`, `minSdk 24`, `targetSdk 36`, solo `arm64-v8a`.
- El APK universal (61 MB) **no cabe** en el almacenamiento del proyecto
  (límite de 50 MB por archivo): se publica la variante arm64, igual que la
  1.0.7 que ya tienen instalada los usuarios.
- Cálculo de actualización verificado: `2008 % 1000 = 8`; un teléfono con
  1.0.7 (`2007 → 7`) recibe el aviso, y uno con 1.0.8 instalada (`8`) **no**
  vuelve a pedir la misma versión.

## 6. Lo que falta del lado del usuario

1. **Aplicar los pasos 10 y 11** de la migración y ejecutar
   `99_verificar.sql` (guía: `docs/fase6-aplicar-migraciones.md`).
2. Configurar la clave de Google Maps (`docs/fase6-mapa-y-voz.md`) y recompilar
   con ella: el APK publicado funciona, pero sin clave usa el mapa alternativo.
3. Probar en un teléfono: login de ambos roles, una entrega con pago parcial,
   caja, rendición, cierre y una ruta con voz.
4. Antes de distribuir por Play Store: crear un keystore de producción y
   `key.properties` (hoy el APK va firmado con la clave de depuración).
