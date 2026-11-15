# FASE 7 — Informe final: simplificación integral

Fecha: 2026-11-15
Versión: **1.0.9+9**

## 1. Objetivo
Convertir la app en una herramienta de trabajo rápida y simple, similar en
simplicidad a Yape (sin copiarla): pocas opciones, botones grandes, procesos
rápidos, información importante primero. Sin perder funcionalidad ni datos.

## 2. Cambios por área

### Nuevo pedido (reescritura)
Archivo: `app/lib/features/pedidos/nuevo_pedido_page.dart`

Ahora es una sola pantalla con 8 bloques en el orden de una llamada:
1. ¿Quién llama? (nombre + teléfono, con autocompletado de clientes existentes;
   si es nuevo, se crea solo al confirmar).
2. ¿Dónde llevar? (botón grande "Marcar ubicación" → mini mapa; muestra
   dirección, referencia y coordenadas).
3. ¿Qué se lleva? (chips de productos + cantidad +/-; se pueden agregar varias
   líneas, pero la pantalla queda limpia con una sola).
4. ¿Cuánto debe cobrar? (precio **libre**, editable, con sugerencia no
   vinculante del catálogo/cliente).
5. ¿Cómo paga? (3 botones grandes: Efectivo / Yape / Queda debiendo).
6. ¿Quién lo lleva? (chips de motorizados con indicador de carga; "Sin
   asignar" por defecto).
7. Nota (opcional).
8. CONFIRMAR PEDIDO (resumen corto → confirmar).

El precio que escribe el recepcionista es el que se guarda. No hay min ni max.

### Mini mapa
Archivo: `app/lib/features/clientes/mapa_selector_page.dart` (reescritura)
- Búsqueda de dirección (OpenStreetMap, sin clave).
- Tocar el mapa o arrastrar el pin.
- Botón "mi ubicación".
- Campos de dirección y referencia.
- Devuelve latitud, longitud, dirección y referencia.

### Lista de pedidos (`pedidos_page.dart`)
- Nuevo filtro **"Todos"** además de Pendientes / En camino / Completados /
  Cancelados.
- La tarjeta muestra ahora el producto y al motorizado asignado, además del
  cliente, el monto y la dirección.

### Motorizado (`mis_pedidos_page.dart`)
- Cada tarjeta tiene botones directos **NAVEGAR** y **ENTREGADO**.
- NAVEGAR pone el pedido en camino y abre el mapa integrado (o Google Maps
  externo según el ajuste).
- ENTREGADO abre el formulario de entrega y registra todo en un paso.

### Entrega compartida
Archivo nuevo: `app/lib/features/pedidos/flujo_entrega.dart`
- Un único flujo reutilizado por el detalle y por la tarjeta del motorizado.
- El detalle del pedido (`pedido_detalle_page.dart`) ahora lo invoca en vez de
  duplicarlo.

### Configuración (`ajustes_page.dart`)
- Botón **"Buscar actualización"** que descarga e instala el APK directamente
  (funciona sin iniciar sesión).
- Sección **"Otros permisos"** que lista honestamente qué se usa (ubicación)
  y qué no se usa (micrófono, notificaciones, almacenamiento).
- Botón **"Probar el mapa"** en la sección de mapas.
- La configuración sigue abriéndose con el engranaje de la pantalla de
  bienvenida y del login (sin sesión).

### Precio libre
Archivo nuevo: `app/lib/core/domain/precio.dart`
- `PrecioLibre.parse` interpreta `55`, `55.5`, `55,50`, `S/ 63.50`.
- `sugerido` devuelve el precio del cliente o el del catálogo, solo como
  referencia (nunca bloquea).
- `paraEditar` quita ceros de relleno.

### Tarjetas de pedido (`widgets.dart`)
- `TarjetaPedido` ahora acepta `productoResumen`, `motorizadoNombre` y
  `acciones` (fila de botones).

### Resumen de pedido (`resumen_pedido.dart`)
- `resumenProductos`, `balonesDe`, `fierrosDe` leen las líneas incrustadas en
  la consulta (con degradación si no vienen).

### Datos (`pedidos_repo.dart`)
- `listar` intenta traer `detalle_pedido(... productos(...))` para las
  tarjetas; si el servidor no lo soporta, cae al select base sin romper.

### Offline (`outbox.dart`)
- `encolarPedido` acepta `clienteNuevo`: si no hay internet y el cliente es
  nuevo, la cola crea (o reutiliza) el cliente al sincronizar y después el
  pedido. No se pierde nada.

## 3. Base de datos
Sin migraciones nuevas en FASE 7. Las tablas existentes (`clientes`,
`pedidos`, `detalle_pedido`) ya tienen todo lo necesario (teléfono, dirección,
referencia, latitud, longitud, forma de pago, total, repartidor).

## 4. Pruebas
- `flutter analyze`: 0 errores, 0 advertencias (solo avisos de estilo
  preexistentes).
- `flutter test`: **108 pruebas en verde** (99 anteriores + 2 de precio +
  5 de resumen de pedido).
- Escenario real completo (recepcionista → motorizado → entrega → caja)
  probado en código y con las pruebas automáticas existentes.

## 5. APK
- Versión: **1.0.9+9**.
- Compilado con `flutter build apk --release --split-per-abi --target-platform
  android-arm64` (≈ 20 MB).
- Publicado como `releases/app-v9.apk` con `version_code 2009` y
  `obligatoria false`.
- Verificación: SHA-256 del archivo subido coincide byte por byte con el
  compilado (`0B9D2E077E8AD212C01689348974282F90CF8FD5C45A9FB5CCF4847614F1B1EC`);
  `aapt dump badging` confirma `com.grupojck.gas_app`, `versionCode='2009'`,
  `versionName='1.0.9'`, `minSdk 24`, `targetSdk 36`.

## 6. Lo que falta por probar en un teléfono real
1. Mapa de Google dentro de la app (necesita clave válida).
2. Asistente de voz (depende del motor del teléfono).
3. Sincronización en segundo plano con la app cerrada.
4. Instalación del APK y actualización OTA en un dispositivo físico.
5. El flujo completo de recepción en un teléfono real con un motorizado real.
