# Migración de base de datos — pasos

Los scripts anteriores (`migration_v3..v8.sql`) fallaban porque el editor SQL
ejecuta el texto por fragmentos y los bloques `DO $$ ... $$` quedaban partidos.

Aquí cada archivo es **pequeño, independiente y reejecutable**: se puede correr
las veces que haga falta sin romper nada ni borrar datos.

## Cómo aplicar

Supabase Dashboard → **SQL Editor** → *New query* → abrir el archivo → **Run**.
Repetir en orden, uno por uno, esperando `Success` antes de pasar al siguiente.

| # | Archivo | Qué hace |
|---|---------|----------|
| 1 | `v7_01_checks.sql` | Permite forma de pago `DEUDA`, estados `NO_ENTREGADO` y pago `PARCIAL` |
| 2 | `v7_02_trigger_entrega.sql` | Al registrar entrega el pedido pasa a `ENTREGADO` |
| 3 | `v7_03_trigger_pago.sql` | Cada cobro entra a la caja abierta (sin duplicar) + función `registrar_ingreso_caja` |
| 4 | `v7_04_guard_reactivar.sql` | Bloquea reabrir pedidos cerrados + `reactivar_pedido` (solo ADMIN) |
| 5 | `v7_05_cuaderno.sql` | `pedidos.origen` + tabla `incidencias` con RLS |
| 6 | `v7_06_rendicion.sql` | `gastos.medio_pago` + `rendiciones` + `cierre_diario` con RLS |
| 7 | `v7_07_asignacion.sql` | Zonas + `asignar_por_zona`, `tomar_pedido`, `liberar_pedido` |
| 8 | `v7_08_permisos.sql` | Solo el motorizado asignado (o ADMIN) registra entrega/cobro |
| 9 | `v7_09_integridad.sql` | Índices únicos (caja abierta, cobro idempotente, rendición diaria) |
| 10 | `v7_10_productos.sql` | `productos.tipo` + depuración de duplicados sin borrar + "Fierro / Balón vacío" como único activo retornable |
| 11 | `v7_11_cuaderno_motorizado.sql` | El motorizado puede registrar su propio pedido y cliente (origen `MOTORIZADO`) |
| 12 | `v7_12_comprobantes.sql` | Columna `pagos.comprobante_url` + permisos de subida al bucket `comprobantes` (foto de Yape) |
| 13 | `v7_13_dias_trabajo.sql` | Columna `perfiles.dias_trabajo` (días de trabajo del motorizado) |
| 14 | `v7_14_sincronizacion.sql` | Gastos del motorizado + Realtime de pagos/gastos/entregas + tabla `ubicaciones_motorizado` (GPS) + reconciliación de pedidos entregados |
| 15 | `v7_15_flujo_simple.sql` | **IMPORTANTE — aplicar este paso sí o sí.** Repone TODAS las políticas del motorizado (corrige "No autorizado"), crea `fondo_vuelto`, añade columnas aditivas y publica Realtime. Es autónomo: se puede ejecutar aunque los pasos 10–14 no estén aplicados. |
| 15b | `v7_15b_republicar_realtime.sql` | Reparación: si el paso 15 falló con `42P01: relation "public.ubicaciones_motorizado" does not exist`, ejecuta este archivo y vuelve a correr el 15. |
| 16 | `v7_16_comprobantes_gasto_falla.sql` | Foto opcional del comprobante en gastos y fallas (`comprobante_url`). Aditivo y reejecutable. |
| 17 | `v7_17_fondo_yape.sql` | El fondo de vuelto puede ser EFECTIVO o YAPE. Solo el efectivo suma al efectivo esperado de la rendición. |

Después: `99_verificar.sql` — todo debe salir en `OK`.

> **Atajo:** si solo quieres destrabar la app ahora mismo, ejecuta primero el
> paso 15 y luego `99_verificar.sql`. El paso 15 reintentar de forma segura
> todo lo que los pasos anteriores pudieron haber dejado sin aplicar.

## Si un paso falla

No continúes: copia el mensaje de error tal cual. Cada paso es independiente,
así que se puede corregir y volver a ejecutar solo ese archivo.

Si el error es de **índice duplicado** en el paso 9, significa que ya hay datos
repetidos en esa tabla; se depuran sin borrar historial antes de reintentar.
