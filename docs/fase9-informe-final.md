# FASE 9 — Informe final: auditoría funcional + calendario + UX simple

Fecha: 2026-11-15
Versión: **1.0.11+11**

## 1. Causa raíz corregida: "No pudimos cargar los productos"
`ProductosRepo.vendibles()` filtraba `.neq('tipo', 'RETORNABLE')` y el fallback
también seleccionaba la columna `tipo`. Si la migración 10 no estaba aplicada,
la columna no existía → PostgrestException 42703 → la lista nunca cargaba.
Ahora: detecta la ausencia de la columna (`esColumnaAusente`), cambia a
columnas base (`id, nombre, capacidad_kg, precio_base`) y trata todos los
productos como vendibles. La app funciona con y sin la migración.

## 2. Cambios principales
- **Calendario** (`calendario_page.dart`): mes con contadores por día; tocar un
  día muestra los pedidos de ese día y los motorizados activos.
- **Días de trabajo del motorizado** (columna `perfiles.dias_trabajo`,
  migración paso 13): configurables con chips Lun–Dom; el calendario los
  respeta. La asignación muestra primero los disponibles, con excepción
  justificada.
- **"Más" reorganizado** en secciones (Operación / Control / Sistema para
  admin; Mi trabajo / Sistema para motorizado).
- **Pantalla principal** con botón grande "NUEVO PEDIDO" y resumen del día.
- **Motorizado "Nuevo registro"**: si hay un solo producto, se auto-selecciona
  y no exige elegirlo. Yape muestra la foto del comprobante en la actividad.
- **Yape fotos** visibles en el detalle de actividad de motorizados.
- **Motorizados activos** accesibles desde Inicio → "Motorizados".

## 3. Base de datos
- Paso 13: `perfiles.dias_trabajo int[]` (NULL = todos los días).

## 4. Pruebas
- `flutter analyze`: 0 errores, 0 advertencias (solo avisos de estilo).
- `flutter test`: **108 pruebas en verde**.

## 5. APK
- Versión: **1.0.11+11**.
- Compilado `flutter build apk --release --split-per-abi --target-platform
  android-arm64` (≈ 20.9 MB).
- Publicado como `releases/app-v11.apk`, `version_code 2011`,
  `obligatoria false`.
- SHA-256 verificado byte por byte:
  `71E9C65B1A94FF651F174E9F3826A1C088AC0C8EEC5EC1F14F6774B526735499`.
- `aapt`: `com.grupojck.gas_app`, `versionCode='2011'`,
  `versionName='1.0.11'`, `minSdk 24`, `targetSdk 36`.

## 6. Migraciones pendientes (pasos 10–13)
Aplicar en orden en el SQL Editor y luego `99_verificar.sql` (todo en `OK`):
- 10: `productos.tipo` + depuración de duplicados + "Fierro / Balón vacío".
- 11: permisos del motorizado para registrar su propio pedido/cliente.
- 12: `pagos.comprobante_url` + bucket `comprobantes`.
- 13: `perfiles.dias_trabajo`.

## 7. Lo que falta por probar en un teléfono real
1. Mapa de Google dentro de la app (necesita clave válida).
2. Asistente de voz.
3. Sincronización en segundo plano con la app cerrada.
4. Instalación del APK y actualización OTA en un dispositivo físico.
5. Flujo completo de recepción + motorizado + rendición + calendario en un
   teléfono real.
