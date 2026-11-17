# FASE 13 — Auditoría funcional real (con base de datos)

**Fecha:** 17/11/2026
**Método:** no se aceptó "existe el código". Se ejecutaron pruebas reales contra
Supabase con login ADMIN y MOTORIZADO, se consultaron las filas resultantes y
se limpiaron todos los datos de prueba (verificado: 0 filas `AUDIT-*` / `audit-*`).

## Resumen ejecutivo

| Área | Resultado |
|---|---|
| Flujo ADMIN → pedido → asignación → motorizado → entrega → pago | **PASS** |
| Cálculo de deudas (casos A, C, D) | **PASS** |
| Balones vacíos y cantidades múltiples (casos A, C, E) | **PASS** |
| Efectivo / Yape / deuda / pago parcial | **PASS** |
| Foto de comprobante Yape persistida | **PASS** |
| Gastos del motorizado y su empresa/usuario | **PASS** |
| Fallas del motorizado | **PASS** |
| Doble entrega bloqueada | **PASS** |
| Aislamiento multiempresa y RLS | **PASS** |
| Cálculos de rendición (fórmula) | **PASS (unitario)** |
| Realtime dos sesiones reales en APK | **PENDIENTE** (sin dispositivos) |
| Google Maps con clave real | **PENDIENTE** (sin clave/API key válida) |
| Historial de ubicación (varios puntos) | **PENDIENTE** (solo última posición) |
| Estados ACEPTADO / LLEGÓ / CERRADO como estados BD | **PENDIENTE** (stepper visual parcial) |
| Navegación y botones en dispositivo | **PARCIAL** (auditoría estática) |

No hay **FAIL** en lo ejecutado. Lo no ejecutado se marca PENDIENTE, no se
reporta como funcional.

---

## A. FUNCIONALIDAD

### Pedidos y clientes — PASS
- `flujo_pedidos_test.dart` 1–4: cliente con dirección/referencia/coordenadas,
  pedido con `empresa_id`, detalle con `empresa_id`, lectura por ADMIN.
- Casos A–F: cada pedido se creó con total, cantidad, precio unitario y
  `uuid_offline`; el total leído coincide con lo guardado.
- Campo `origen = MOTORIZADO` verificado en el cuaderno del motorizado.

### Asignación — PASS
- Test 5: ADMIN asigna → estado `ASIGNADO` leído de la base.
- Test 6: MOTORIZADO ve el pedido con dirección y coordenadas **del cliente**.

### Entregas — PASS
- Test 8: `EN_CAMINO` → entrega → pago → movimiento de balón → `ENTREGADO`.
- Test 9 / caso duplicado: segunda entrega rechazada (`pedido_id` UNIQUE).

### Pagos — PASS
- Caso A: EFECTIVO 50 → deuda 0.
- Caso B: YAPE 50 → deuda 0, `comprobante_url` leído desde ADMIN.
- Caso C: sin pago → deuda 50.
- Caso D: total 180, pago 100 → deuda 80.

### Deuda — PASS
- Unica fuente de verdad: `calcularDeudas()` en `core/domain/deuda.dart`.
- En cada caso se consultaron `pedidos ENTREGADO` y `pagos` reales y se pasaron
  a esa función; el resultado coincide con lo que muestra la app.
- No se encontró ninguna pantalla que calcule deuda con otra regla.

### Balones — PASS
- Unica fuente: `calcularSaldosActivos()`.
- Caso A: 1 entregado / 1 devuelto → pendiente 0.
- Caso C: 1 entregado / 0 devueltos → pendiente 1.
- Caso E: 3 entregados / 2 devueltos → pendiente 1.

### Gastos — PASS
- Caso F: gasto combustible 30 con `empresa_id` y `usuario_id`; ADMIN lo lee.
- No se suma como venta ni genera deuda del cliente.

### Fallas — PASS
- Test final: incidencia con `tipo=FALLA`, monto, empresa y motorizado;
  ADMIN la lee con los mismos valores.

### Movimientos — PASS (datos) / PARCIAL (pantalla)
- Los movimientos salen de pedidos, pagos, gastos e incidencias reales.
- La pantalla `MovimientosPage` usa esos repositorios y Realtime; no se probó
  visualmente en dispositivo.

### Seguimiento — PARCIAL
- Última ubicación con frescura honesta y GPS mientras hay pedido activo: **PASS (código)**.
- Recorrido con varios puntos históricos: **PENDIENTE** (solo se guarda la última fila).
- Distancia/ETA: **PENDIENTE** sin clave de Google Directions.

### Rendición — PARCIAL
- Fórmula `fondo + efectivo − gastos efectivo = esperado` y diferencia: **PASS (unitario)**.
- Datos de pedidos/gastos/balones/fondos que alimentan la pantalla: **PASS (DB)**.
- Enviar/declarar y aprobar rendición desde la APK con dos sesiones: **PENDIENTE**.

### Caja — PASS (parcial)
- Cada pago dispara `registrar_ingreso_caja`; la limpieza eliminó los
  `movimiento_caja` por `referencia_id` en las pruebas. No se auditó el cierre
  de caja en pantalla.

---

## B. CÁLCULOS

| Regla | Evidencia | Resultado |
|---|---|---|
| Cantidad × precio unitario = total | Caso D: 2 × 90 = 180 leído de BD | PASS |
| Pagado ≤ total | No se permitió pagar de más en ningún caso | PASS |
| Deuda = total entregado − pagos | Casos A/C/D con función pura sobre BD | PASS |
| Deuda nunca negativa | `calcularDeudas` descarta saldos ≤ 0.009 | PASS |
| Balones entregados − devueltos | Casos A/C/E | PASS |
| Yape no es efectivo | Fórmula de rendición separa ambos | PASS |
| Gasto no es venta | Caso F | PASS |
| Efectivo esperado = fondo + efectivo − gastos efectivo | `rendicion_flujo_test.dart` | PASS |

## C. NAVEGACIÓN

Auditoría estática de todos los `context.go/push` del proyecto: las 37 rutas
usadas existen en `main.dart` (`/pedidos`, `/pedidos/nuevo`, `/movimientos`,
`/mi-registro`, `/declarar-rendicion`, `/seguimiento`, `/rendicion`, etc.).
No hay `onPressed: () {}` vacíos ni botones sin acción.

**Resultado: PARCIAL** — no hay teléfono para recorrer las rutas en vivo.

## D. BOTONES

- No se encontraron handlers vacíos.
- Botones de escritura principales tienen estado `_guardando` y muestran error
  con `traducirError` (pedido, entrega, gasto, falla, rendición, fondo).
- **Mejora pendiente:** no todos los botones secundarios bloquean doble toque.

## E. REALTIME

- Un único canal global (`RealtimeService`) suscrito a 14 tablas.
- `99_verificar.sql` devolvió OK para las tablas-publicadas (confirmado por el usuario).
- `SyncBus` avisa a pedidos/dinero/ubicaciones/movimientos/rendiciones.
- **PENDIENTE:** prueba con dos APK/sesiones simultáneas reales (no hay dispositivos).

## F. SUPABASE

Consultas reales posterior a cada acción: pedidos, entregas, pagos, movimientos,
gastos, incidencias y perfiles. Datos coincidentes con la UI esperada.
Datos de prueba eliminados y verificado 0 restantes.

## G. GOOGLE MAPS

- Dependencia, permisos y `meta-data` con `${mapsApiKey}` correctos.
- GoogleMap nativo en ruta, seguimiento y selector; `Ir al cliente` usa
  latitud/longitud del cliente.
- **PENDIENTE:** clave válida y prueba en teléfono. Sin clave se muestra aviso.

## H. SEGURIDAD

- Test 3: detalle sin `empresa_id` rechazado por RLS.
- Test 7: motorizado no puede crear pedido `origen=ADMIN`.
- Test 13/14: ADMIN no ve otra empresa y no puede escribir en ella.
- No se usa `service_role` dentro del APK (solo en pruebas/Scripts).

## I. APK

- `flutter analyze`: 0 errores, 0 warnings (29 infos).
- `flutter test`: **134 pruebas en verde** (incluye 2 pruebas de integración
  que se saltan sin credenciales).
- Pruebas reales con credenciales: **22 PASS**
  (14 `flujo_pedidos_test.dart` + 8 `casos_reales_test.dart`).
- `flutter build apk --release --split-per-abi --target-platform android-arm64`: OK.

## J. RESULTADO FINAL

**PASS** — pedidos, clientes, asignación, entregas, pagos, Yape y comprobante,
deudas, balones (incluye múltiples), gastos, fallas, doble entrega, multiempresa,
RLS, cálculos, Outbox/idempotencia, analyze, test y build.

**PARCIAL** — rendición (fórmula y datos probados, envío/aprobación en APK no),
movimientos y navegación (auditoría estática), caja.

**PENDIENTE** — Realtime con dos dispositivos, Google Maps con clave real,
historial de puntos GPS, estados ACEPTADO/LLEGÓ/CERRADO como estados persistidos,
doble toque en botones secundarios.

No se declara el sistema terminado: lo anterior es lo que efectivamente se
comprobó, y lo no comprobado está marcado como pendiente.
