# FASE 15 — Evidencia de Yape en TODOS los pagos

## Qué se corrigió

Antes la foto del comprobante solo se podía tomar en la **entrega de pedidos**
y en el **registro manual del motorizado**. Faltaba en los pagos sueltos.

Ahora al elegir **Yape** aparece siempre el selector de foto (cámara o galería)
en:

1. Entrega de pedido (`entrega_sheet.dart`).
2. Registro manual del motorizado (`registro_pedido_page.dart`).
3. Pago de una deuda desde **Deudas** (`deudas_page.dart`).
4. Pago desde la **ficha del cliente** (`pago_sheet.dart`).
5. **Cobros** sueltos (`cobros_page.dart`).

Componente único reutilizable: `core/ui/comprobante_picker.dart`.
Servicio único: `core/data/pago_con_comprobante.dart`.

## Regla

- Si el pago es Yape, se pide la foto como evidencia.
- Si no se toma, aparece un diálogo: **"Volver a la foto"** o
  **"Continuar sin foto"** (nunca se finge que se guardó).
- La foto se sube a Supabase Storage (`bucket comprobantes`) y la URL se guarda
  en `pagos.comprobante_url`.
- Si no hay red, la ruta local se guarda en el **Outbox** y se sube al
  sincronizar. El pago no se duplica (`uuid_offline`).
- ADMIN puede ver la foto desde el detalle del pedido (**VER COMPROBANTE**) y
  desde Movimientos/Mi registro.

## Verificación

- `flutter analyze`: 0 errores, 0 warnings.
- `flutter test`: **137 pruebas en verde**, incluidas 2 nuevas de
  `pago_sheet_test.dart` que comprueban que al elegir Yape aparecen
  "Tomar foto"/"Galería" y el aviso si no hay comprobante.
- Pruebas reales contra Supabase: **23 PASS**, incluida la del fondo Yape del
  paso 17. Datos de prueba eliminados (0 restantes).
- Build OK. APK **1.0.17+17**, `versionCode` 2017, `releases/app-v17.apk`.
  SHA-256: `A5093347D95533345B221160D34D1C4488B1B6D47B0C499702F7E519BA1538CA`.

## Pendiente

Verificar en teléfono real la toma de foto y la visualización del comprobante
(no hay dispositivo en este entorno).
