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

Después: `99_verificar.sql` — todo debe salir en `OK`.

## Si un paso falla

No continúes: copia el mensaje de error tal cual. Cada paso es independiente,
así que se puede corregir y volver a ejecutar solo ese archivo.

Si el error es de **índice duplicado** en el paso 9, significa que ya hay datos
repetidos en esa tabla; se depuran sin borrar historial antes de reintentar.
