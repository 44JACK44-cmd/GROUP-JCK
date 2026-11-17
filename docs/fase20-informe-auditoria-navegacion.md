# FASE 20 — Auditoría y reestructuración de navegación y UX

## 1. Pantallas y rutas identificadas

**Públicas:** `/splash`, `/welcome`, `/login`, `/registro-empresa`, `/ajustes`.
**Shell (barra inferior):** `/inicio`, `/pedidos`, `/clientes`, `/cobros`, `/mas`,
`/mis-pedidos`, `/historial`, `/mi-registro`, `/movimientos`, `/calendario`, `/mas-moto`.
**Completas:** `/pedidos/nuevo`, `/balones`, `/deudas`, `/caja`, `/rendicion`,
`/conciliacion`, `/declarar-rendicion`, `/aprobacion-rendiciones`, `/cierre-diario`,
`/reportes`, `/motorizados`, `/motorizados-actividad`, `/seguimiento`,
`/mi-registro/pedido`, `/mi-registro/gasto`, `/mi-registro/incidencia`.
**Redirecciones:** `/reparto` → `/mis-pedidos`, `/combustible` → gasto con
categoría Combustible, `/devolucion-balon` → `/balones`.

## 2. Errores de navegación encontrados

- Doble acceso a **Caja** (panel principal + barra inferior) con riesgo de
  confusión y retorno inconsistente.
- Doble acceso a **Movimientos** en el motorizado (panel + barra inferior).
- Ruta `/motorizados` (altas/edición) sin ningún acceso visible desde la app.
- Varias pantallas secundarias sin botón "Volver" explícito (Caja, Rendición,
  Balones, Movimientos, Motorizados).
- Botón atrás de Android podía cerrar la app al quedar sin stack interno.

## 3. Botones duplicados encontrados

| Duplicado | Resolución |
|---|---|
| Caja en inicio + barra inferior | Se eliminó el acceso del inicio; queda la barra inferior. |
| Movimientos en inicio motorizado + barra inferior | Se eliminó el botón del inicio. |
| Deudas en inicio + "Historial de deudas" en Más | Se conservan con propósitos distintos: cobrar vs consultar historial. |
| Balones en inicio + "Control de balones" en Más | Igual: acceso operativo vs inventario. |
| Combustible / Gastos | `/combustible` redirige al formulario de gasto con categoría preseleccionada. |
| Devolución de balones / Balones | `/devolucion-balon` redirige a Balones (módulo único). |
| Motorizados (actividad) / Motorizados (altas) | Se aclaran en Más: "Equipo y días de trabajo" vs "Altas y edición". |

## 4. Funcionalidades redundantes identificadas

- Registro de combustible fuera de Gastos → integrado como categoría.
- Devolución de balones como pantalla propia → integrada en Balones.
- Fierros como módulo independiente → dato dentro del contexto de Balones.

## 5. Pantallas integradas / eliminadas

- `CombustiblePage`: ya no se abre; la ruta apunta al formulario de gasto.
- `DevolucionBalonPage`: ya no se abre; la ruta apunta a Balones.
- No se borraron archivos ni datos: solo se unificaron los accesos.

## 6. Cambios en ADMIN

- Panel con datos reales: pendientes, en camino, entregados, motorizados activos,
  rendiciones pendientes y alerta de rendiciones con diferencia.
- Panel de **Rendiciones pendientes** con acceso directo a revisión.
- Acceso a "Altas y edición de motorizados" desde Más.
- Sin acceso duplicado a Caja.

## 7. Cambios en MOTORIZADO

- Tarjeta de **Próximo pedido** con cliente, dirección/referencia, estado,
  **VER PEDIDO** e **IR AL CLIENTE** (Google Maps con coordenadas del cliente).
- Resumen real del día: pedidos, ventas, efectivo, Yape, gastos, balones y
  estado de rendición.
- Acciones directas sin duplicar la barra inferior.

## 8. Correcciones del botón atrás de Android

- `PopScope` global: pop interno → Inicio → confirmación de salida.
- `NavegacionService` mantiene la ruta actual y los avisos.
- `AppBarVolver` en Caja, Rendición, Balones, Movimientos, Motorizados,
  Detalle de pedido y Mi rendición.
- No existen `pushReplacement` ni stacks anidados nuevos.

## 9. Archivos modificados

`main.dart`, `core/navegacion/navegacion_service.dart` (nuevo),
`core/ui/app_bar_volver.dart`, `features/shell/app_shell.dart`,
`features/home/home_page.dart`, `features/home/home_moto_page.dart`,
`features/mas/mas_page.dart`, `features/finanzas/caja_page.dart`,
`features/rendicion/rendicion_page.dart`, `features/rendicion/declarar_rendicion_page.dart`,
`features/balones/balones_page.dart`, `features/movimientos/movimientos_page.dart`,
`features/motorizados/motorizados_actividad_page.dart`,
`features/pedidos/pedido_detalle_page.dart`, pruebas y documentación.

## 10. Pruebas ejecutadas

- `flutter analyze`: **0 errores, 0 warnings** (97 infos).
- `flutter test`: **143 pruebas en verde**.
- Pruebas reales Supabase: **23 PASS**, sin datos residuales.
- `flutter build apk --release --split-per-abi --target-platform android-arm64`: OK.
- APK **1.0.22+22**, `versionCode` 2022.
  SHA-256: `000B291F0CE30B561834FCA6EF33D698FE08C3B0D139FD7A1B60C0CC94E24945`.

## 11. Errores pendientes

- Falta la prueba física en Android del botón/gesto atrás, la navegación entre
  todos los módulos y el cambio de tema en dispositivo (no hay teléfono aquí).
- No se agregaron notificaciones push nativas (requieren FCM y permisos);
  existe el aviso interno en tiempo real.
- No se inventaron horas de aceptación/salida/llegada: la base solo guarda
  `fecha` y `estado`, por lo que el informe detallado de hitos queda limitado
  a la información real disponible.

No se declara terminado solamente porque compile.
