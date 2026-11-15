# FASE 8 — Informe final: pedidos unificados + Mi registro + rendición en tiempo real

Fecha: 2026-11-15
Versión: **1.0.10+10**

## 1. Objetivo
Unificar la lógica de pedidos: un solo concepto de pedido (con `origen`
RECEPCIONISTA/MOTORIZADO). El motorizado, al registrar desde "Mi registro",
crea un pedido real ya entregado, con pago, balón y movimiento de caja. Todo
fluye automáticamente a recepcionista, admin, rendición y caja.

## 2. Cambios principales

### Mi registro unificado (`registro_pedido_page.dart`, reescritura)
- Cliente (búsqueda/creación), teléfono, dirección, referencia, ubicación.
- Hora editable (por defecto la actual).
- Producto + cantidad + precio libre.
- Forma de pago: Efectivo / Yape / Queda debiendo.
- Si Yape: botón para tomar/elegir foto del comprobante (preview incluida).
- Balón vacío dejado: Sí/No.
- Observación.
- Al guardar (online): crea cliente + pedido (origen MOTORIZADO, repartidor = él,
  fecha = hora elegida) + entrega completa (pago, balón, caja) +
  comprobante subido al bucket `comprobantes`.
- Al guardar (offline): encola `pedido_completo` con todos los datos y la foto
  local; al sincronizar crea todo en orden, sin duplicados.

### Comprobante de Yape
- Bucket `comprobantes` (público, 5 MB, jpeg/png/webp) creado en Supabase.
- Columna `pagos.comprobante_url` (migración paso 12).
- `ComprobanteService` sube el archivo y devuelve la URL pública (best-effort).
- `PagosRepo.registrar` y `EntregasRepo.registrarEntrega` aceptan
  `comprobanteUrl`.

### Outbox
- Nuevo tipo de operación `pedido_completo` con `_insertarPedidoCompleto`:
  cliente → pedido (ENTREGADO) → detalles → entrega → pago (con comprobante) →
  balón. Idempotente por `uuid_offline` y por las unicidades de la base.

### Rendición en tiempo real
- `rendicion_page.dart` y `home_moto_page.dart` se suscriben a cambios de
  `pedidos`, `pagos` y `gastos` y recalculan automáticamente.

### Actividad de motorizados (recepcionista/admin)
- Nueva página `motorizados_actividad_page.dart`: tarjeta por motorizado con
  pedidos, ventas, efectivo, Yape, gastos, deudas y balones; tocar abre el
  detalle cronológico (pedidos + gastos) del día.
- Accesible desde Inicio → "Motorizados".
- Se actualiza en tiempo real.

### Mi jornada (motorizado)
- `home_moto_page.dart` muestra ahora también gastos y efectivo esperado.

### Configuración
- Ya disponible desde el engranaje de la pantalla de bienvenida/login (sin
  sesión), con permisos, mapas, audio, conexión, actualizaciones e información.

## 3. Base de datos
- Paso 12: `pagos.comprobante_url` + políticas de subida al bucket
  `comprobantes`.
- Bucket `comprobantes` creado en Supabase (público, 5 MB).

## 4. Pruebas
- `flutter analyze`: 0 errores, 0 advertencias (solo avisos de estilo).
- `flutter test`: **108 pruebas en verde**.
- Escenarios 1–6 (recepcionista, motorizado propio, Yape con foto, deuda,
  gasto, offline) verificados en código.

## 5. APK
- Versión: **1.0.10+10**.
- Compilado `flutter build apk --release --split-per-abi --target-platform
  android-arm64` (≈ 20.9 MB).
- Publicado como `releases/app-v10.apk`, `version_code 2010`,
  `obligatoria false`.
- SHA-256 verificado byte por byte:
  `8FA07D9C41424C4C269F23C76EC67339D33B2411A98939D5507CF6E3B7DBCD57`.
- `aapt`: `com.grupojck.gas_app`, `versionCode='2010'`, `versionName='1.0.10'`,
  `minSdk 24`, `targetSdk 36`.

## 6. Lo que falta por probar en un teléfono real
1. Mapa de Google dentro de la app (necesita clave válida).
2. Asistente de voz.
3. Sincronización en segundo plano con la app cerrada.
4. Instalación del APK y actualización OTA en un dispositivo físico.
5. Tomar foto del comprobante con la cámara y verificar que se sube.
6. Flujo completo de recepción + motorizado + rendición en un teléfono real.
