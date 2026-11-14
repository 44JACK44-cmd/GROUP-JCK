# FASE 6 — ETAPA A: Diagnóstico de auditoría general

Fecha: 2026-11-13
Alcance: repositorio completo (64 archivos Dart, 7 SQL) + **base de datos Supabase en vivo** (consultas reales con token ADMIN y MOTORIZADO).
Método: 4 auditorías de código en paralelo (esquema SQL, flujo pedidos/entregas, finanzas, auth/roles/UX) + pruebas RLS/flujo ejecutadas contra la BD real.
**No se modificó nada.** Cero cambios destructivos.

---

## VEREDICTO

La app **compila y tiene 54 pruebas verdes**, pero el sistema real **no funciona de punta a punta**. La causa raíz dominante es una sola:

> **La base de datos en producción está varias migraciones por detrás del código.**
> Las migraciones **v3 (triggers), v4, v5 y v6 nunca se aplicaron**.

Todo lo demás (rendición que no suma, caja que no cuadra, conciliación que acusa diferencias falsas, motorizado que no recibe pedidos) es **síntoma** de esa desconexión + una capa de bugs de cliente encima.

---

## 1. ESTADO REAL DE LA BASE DE DATOS (verificado en vivo, no por lectura de archivos)

### 1.1 Migraciones NO aplicadas

| Elemento que falta | Quién lo necesita | Efecto hoy |
|---|---|---|
| tabla `rendiciones` | rendición, aprobación | Pantalla de rendición **falla con 404** |
| tabla `cierre_diario` | cierre de jornada | Cierre diario **falla con 404** |
| tabla `incidencias` | registro de incidencias | Incidencias **fallan con 404** |
| `pedidos.origen` | conciliación recepción vs motorizado | Conciliación **revienta con 42703** |
| `gastos.medio_pago` | gastos por medio de pago | Todo gasto cae como EFECTIVO |
| `clientes.zona`, `perfiles.zona` | `asignar_por_zona` (v6) | RPC **no existe** en BD |
| `perfiles.email` | login por email en某些 flujos | 42703 |
| `movimiento_caja.metodo`, `.pedido_id` | cuadre por método / trazabilidad | Cuadre imposible de trazar |

### 1.2 Triggers de `migration_v3` NO están activos (prueba directa)

| Prueba ejecutada | Resultado esperado | Resultado real |
|---|---|---|
| INSERT `entregas` sobre pedido `EN_CAMINO` | trigger `trg_entrega_pedido_estado` → pedido `ENTREGADO` | pedido **sigue `EN_CAMINO`** ❌ |
| INSERT `pagos` S/ 25 con caja `ABIERTA` | trigger `trg_pago_ingreso_caja` → fila en `movimiento_caja` | `movimiento_caja` **vacía** ❌ |

**Consecuencia:** ninguna entrega cambia estado sola, y **ningún cobro entra a caja**. Por eso `movimiento_caja` tiene **0 filas** en producción y el cuadre de caja no puede funcionar nunca.

### 1.3 RLS en vivo (token MOTORIZADO)

| Prueba | Resultado | Veredicto |
|---|---|---|
| Ve los pedidos | solo sus 4 pedidos | ✅ correcto |
| Ve perfiles ajenos | solo el propio | ✅ correcto |
| Ve cajas | `[]` | ✅ correcto |
| INSERT pedido | 42501 denegado | ✅ correcto |
| PATCH pedido **ajeno** | 0 filas, sin cambios | ✅ correcto |
| **PATCH pedido sin asignar ("Tomar")** | **0 filas, sin error** | ❌ **BUG: falso éxito** |
| PATCH pedido propio | OK | ✅ |
| INSERT `entregas` (sobre cualquier pedido de la empresa) | **aceptado** | ❌ sin validación de propiedad |
| INSERT `pagos` (sobre cualquier pedido) | **aceptado** | ❌ sin validación de propiedad |
| INSERT `gastos` | 42501 denegado | ❌ **bloquea** rendición y "Mi registro" |
| INSERT `rendiciones` / `incidencias` | tabla no existe | ❌ migración pendiente |

---

## 2. ERRORES ENCONTRADOS — CLASIFICADOS POR IMPACTO

### 🔴 P0 — El sistema no funciona hoy (bloquea el negocio)

| # | Error | Evidencia |
|---|---|---|
| P0-1 | **Migraciones v3/v4/v5/v6 sin aplicar** → 3 tablas y 7 columnas ausentes, triggers muertos | §1.1, §1.2 |
| P0-2 | **"Tomar pedido" es un no-op silencioso**: RLS evalúa `repartidor_id = uid()` sobre la fila vieja (NULL) → 0 filas; la app muestra *"Tomaste el pedido."* | `schema.sql:379-383`, `pedidos_repo.dart:248-251`, `mis_pedidos_page.dart:129` |
| P0-3 | **`Outbox.procesar()` jamás se llama** en toda la app → lo pedido/entregado sin internet **nunca sincroniza**; el mensaje "se enviará sola" es falso | `outbox.dart:120` (0 llamadores) |
| P0-4 | **`movimiento_caja` vacía**: sin trigger, ningún cobro ni gasto entra a caja → cuadre = inventar números | §1.2 |
| P0-5 | **Rendición no existe en BD** y en el cliente se calcula en Dart con `limit(5000)` → pantalla rota + totales truncables | `rendicion_repo.dart:89-126` |
| P0-6 | **Motorizado no puede leer ni escribir `gastos`** (RLS solo-admin) → `DeclararRendicion` y `HomeMoto` fallan en `Future.wait` y muestran 0/stale con `catch(_) {}` | `schema.sql:441-443`, `rendicion_repo.dart:119`, `home_moto_page.dart:43-61` |

### 🟠 P1 — Dinero mal calculado (riesgo financiero directo)

| # | Error | Evidencia |
|---|---|---|
| P1-1 | **`caja_repo.resumen()` suma TODO el histórico**: sin `.eq('caja_id')` ni filtro de fecha real (`DateTime(2000)`→`DateTime(2100)`) → "Saldo" que se ofrece al cerrar es de toda la empresa, no de la caja | `caja_repo.dart:153-164, 209`, `caja_page.dart:43` |
| P1-2 | **`cerrar()` no valida estado** → se puede cerrar dos veces y **reescribir una caja cerrada**; `registrarIngreso/Gasto` aceptan `caja_id` cerrado | `caja_repo.dart:88-92, 96-145` |
| P1-3 | **No hay UNIQUE parcial de caja abierta** → dos cajas ABIERTA simultáneas reparten los cobros al azar | `schema.sql:173-181` |
| P1-4 | **Cobros fuera de horario de caja se pierden para siempre** (trigger solo inserta si hay caja abierta, sin cola ni aviso) | `migration_v3.sql:100-113` |
| P1-5 | **Sin `UNIQUE(origen, referencia_id)` en `movimiento_caja`** → un pago re-insertado duplica el ingreso | `schema.sql:183-194` |
| P1-6 | **Doble cobro posible**: si `_cargar()` falla tras una entrega exitosa, el `catch` encola la entrega otra vez con uuids nuevos → `entregas` se salta (UNIQUE) pero **el pago se inserta otra vez** | `pedido_detalle_page.dart:203-258`, `outbox.dart:226-233` |
| P1-7 | **Gastos sin `medio_pago` en todas las escrituras** → nunca se descuentan por método; combustible queda fuera de "Total gastos" | `registro_gasto_page.dart:58-64`, `caja_repo.dart:137-144` |
| P1-8 | **Cierre diario mezcla Yape con efectivo**: `gastosTotal` no filtra `medio_pago` → un gasto en Yape reduce el efectivo esperado | `rendiciones_repo.dart:186-190` |
| P1-9 | **`diferencias` se guarda siempre `0.0`** y `monto_declarado` **nunca se lee** → no existe cuadre real | `rendiciones_repo.dart:205`, `caja_repo.dart:91` |
| P1-10 | **Diferencia de rendición calculada con ventana de 24 h** (ignora `fecha` de la rendición) y sin descontar gastos → falsos faltantes en rojo | `aprobacion_rendiciones_page.dart:51-59` |
| P1-11 | **4 implementaciones distintas de "lo que se debe"** con `limit` distintos (2000/5000/10000) → 4 números distintos para el mismo concepto | `deuda.dart`, `clientes_repo:164`, `informes_repo:181`, `caja_repo:164`, `rendicion_repo:247` |
| P1-12 | **Cobro de deuda sin `pedido_id` no entra en `cobrado`** de la rendición → rendición dice "pendiente", deudas dice "pagado", caja dice "ingresó" | `rendicion_repo.dart:103-106`, `cobros_page.dart:63-69` |
| P1-13 | **Desfase horario de 5 h**: `DateTime.toIso8601String()` local sin offset interpretado como UTC → "Hoy" arranca 19:00 del día anterior | `rendicion_repo.dart:78-85`, `formato.dart:74-77` |
| P1-14 | **Sin `UNIQUE(motorizado_id, fecha)` en `rendiciones`** → doble declaración con 2 dispositivos | `migration_v5.sql:23-41` |

### 🟡 P2 — Flujo roto o mentiroso para el usuario

| # | Error | Evidencia |
|---|---|---|
| P2-1 | **"Reabrir pedido" siempre falla**: UPDATE directo choca con `trg_pedidos_guarda_estado`; el RPC `reactivar_pedido` (vía correcta) **nunca se llama**; `P0001` no está traducido | `pedidos_repo.dart:330-343`, `sb.dart:24-51` |
| P2-2 | **Desasignar no escribe `repartidor_id: null`** → pedido `NUEVO` con repartidor viejo = huérfano, in-tomable | `pedidos_repo.dart:248-251` |
| P2-3 | **Conciliación acusa diferencias falsas siempre**: `_selectPedido` no selecciona `origen` → todos los pedidos caen en "Recepción" | `pedidos_repo.dart:345-347`, `conciliacion_page.dart:39-40` |
| P2-4 | **"Cancelar" en la aprobación aprueba igual** (`justificacion == null && estado != aprobada` no aborta) | `aprobacion_rendiciones_page.dart:45-47` |
| P2-5 | **El motorizado puede auto-aprobar su propia rendición** (política `update` sin restringir columnas) — *se manifestará cuando v5 se aplique* | `migration_v5.sql:57-63` |
| P2-6 | **`asignar_por_zona` es `SECURITY DEFINER` sin validar empresa** → escritura cross-tenant — *se manifestará con v6* | `migration_v6.sql:23-69` |
| P2-7 | **El motorizado no puede registrar pedidos ni clientes** (RLS `insert` solo-admin) → el "cuaderno digital" de v4 falla con 42501 | `schema.sql:347,377`, `registro_pedido_page.dart:136,156` |
| P2-8 | **`registrarNoEntregado` roto y sin botón**: el trigger lo deja `ENTREGADO` y el guard rechaza el cambio; además `UNIQUE(pedido_id)` bloquea la entrega posterior real | `entregas_repo.dart:232-266` |
| P2-9 | **Detalle nunca refresca el pedido**: `_cargar()` no re-consulta `widget.pedido`; sin realtime en el detalle; las acciones que no hacen `pop(true)` dejan la lista congelada | `pedido_detalle_page.dart:55-82`, `192-264` |
| P2-10 | **Tile "Cobros" del motorizado muerto** → rebota a `/mis-pedidos` (ruta admin) | `mas_page.dart:151`, `main.dart:53,187-189` |
| P2-11 | **7 accesos de "Configuración/Audio/Permisos/Ayuda"** en home, todos a `/mas`; no hay pantalla propia | `home_page.dart:190-202` |
| P2-12 | **`catch (_) {}` vacíos**: red se muestra como "sin datos" en rendición, cierre, homes, conciliación; auditoría se pierde en silencio | `rendicion_page:95`, `auditoria_repo:32-34` |
| P2-13 | **`auth_controller` hace `signOut()` ante cualquier error de red** al cargar el perfil | `auth_controller.dart:72-76` |
| P2-14 | **Observaciones de entrega no se guardan** (no hay columna) y solo van a `auditoria` (lectura solo-admin) → el motorizado nunca las ve | `entrega_sheet:324-331`, `entregas_repo:217` |
| P2-15 | **Observación del gasto capturada pero no insertada** | `registro_gasto_page.dart:130-137` vs `58-64` |
| P2-16 | **Crash potencial**: `double.parse('')` si el campo de monto queda vacío | `entrega_sheet.dart:83-85` |
| P2-17 | **Realtime solo en `pedidos`**; sin realtime en rendiciones, pagos, caja, gastos → pantallas stale hasta recarga manual | `migration_v3.sql:216-227` |
| P2-18 | **Router recreado en cada `build()`** y solo 5 rutas protegidas (`/reportes`, `/motorizados`, `/rendicion`, `/caja`, `/conciliacion`… alcanzables por motorizado sin autogateo) | `main.dart:172,187-195` |
| P2-19 | **`schema.sql` L318-324 borra TODAS las políticas** de `public` → re-ejecutarlo destruye las políticas de v4/v5 | `schema.sql:318-324` |
| P2-20 | **No existe el rol `RECEPCIONISTA`** (0 coincidencias; CHECK solo `ADMIN/MOTORIZADO`) — el requisito lo asume | `schema.sql:25` |

### 🔵 P3 — UX / rendimiento / deuda técnica

- Home admin: 8 accesos al mismo menú "Más"; 3 destinos a `/pedidos`; pestaña resaltada mal en `/mis-pedidos` para admin (`app_shell.dart:80-81`).
- Mezcla `push`/`go` → pila de navegación acumulada (`home_page.dart:118,161,168,190-195,202,221`).
- Errores hardcodeados `Color(0xFF146B5D)` en login en vez de `AppTheme`.
- Sin `RefreshIndicator` en rendición, cierre, y en caja cuando está cerrada (imposible refrescar).
- Sin "olvidé mi contraseña"; `login_page.dart:121` usa `pop()` en vez de `go('/welcome')`.
- `productos` sin `UNIQUE(empresa_id, nombre)` → **productos duplicados confirmados en BD** (2× cada Balón).
- Índices ausentes: `pedidos(cliente_id)`, `pedidos(numero)`, `movimiento_caja(fecha)`, `cajas(estado)`, `gastos(fecha)`.
- `pedidos.version` nunca se incrementa → el "optimistic locking" documentado no existe.
- Sin `TTS`, sin `permission_handler`, sin `google_maps_flutter` → ETAPA C pendiente de dependencias.

---

## 3. FIERRO / BALÓN VACÍO (requisito §6)

**Estado actual:** no están duplicados **porque no existen como productos** — solo hay `Balón 10/15/45 kg`.
- El **fierro** solo vive en `movimiento_fierro` (saldo), nunca se factura; la cantidad que declara el motorizado **no se cruza con `detalle_pedido`**.
- El **balón vacío** vive en dos sitios coherentes: `entregas.estado_bal_on_vacio` (flag) y `movimiento_bal_on` tipo `DEVOLUCION_VACIO` (saldo).
- **Riesgo real de duplicación:** `productos` no tiene `UNIQUE(empresa_id,nombre)` ni columna `tipo/es_retornable` → si alguien crea "Fierro" o "Balón vacío" como producto, el mismo activo se contaría dos veces (facturado + saldo).
- **Riesgo de notas:** las notas/observaciones **no generan productos hoy** ✓ (correcto), pero sí existen campos capturados que no se guardan (P2-14, P2-15).
- **Acción ETAPA B-6:** migración no destructiva = `UNIQUE(empresa_id, nombre)` + columna `tipo` (`PRODUCTO|RETORNABLE`) + `INSERT` canónico de "Fierro / Balón vacío" como **un solo** concepto, sin tocar pedidos históricos.

---

## 4. PLAN DE CORRECCIÓN (ETAPA B → G)

| Etapa | Contenido | Depende de |
|---|---|---|
| **B0** | **Aplicar migraciones v3+v4+v5+v6 en el Dashboard SQL Editor** (tablas, columnas, triggers, RLS) + `UNIQUE` de productos y de caja abierta + `UNIQUE(origen, referencia_id)` en `movimiento_caja` | acceso al Dashboard (manual) |
| B-1 | Configuración **pre-login** (engranaje en login y welcome, pantalla no sensible) | nada |
| B-2 | Asignación: `tomar_pedido` con filas afectadas verificadas, desasignar con `NULL`, `origen` en `_selectPedido` | B0 (v4) |
| B-3 | Entrega: validación de propiedad en servidor, separar entrega de `_cargar()`, arreglar `registrarNoEntregado`, `pop(true)` en todas las acciones | B0 |
| B-4 | Rendición automática: gastos legibles por motorizado, cálculo en SQL, realtime, filtro de fechas con offset | B0 (v5) |
| B-5 | Cuadre de caja: `resumen` por `caja_id`, cierre único, `diferencias` real, gastos por `medio_pago`, cola de cobros sin caja | B0 (v3) |
| B-6 | Fierro/balón: normalización no destructiva | B0 |
| C | Google Maps integrado + rutas + TTS + permisos | paquetes + API key |
| D | UX: home simplificado, rutas protegidas, tablas stale | — |
| E | Realtime ampliado + `Outbox.procesar()` + indicador de cola | B2-B5 |
| F | 27 pruebas obligatorias + regresiones | todo |
| G | `analyze` + `test` + APK release + verificación | F |

---

## 5. LÍNEA BASE (verificación del entorno)

- `flutter analyze` en ejecución (resultado pendiente en este documento).
- Última verificación conocida: 19 info / 0 errores; `flutter test` 54/54; APK `app-v7.apk` publicado (v1.0.7+7, commit `8aebd7b`).

---

## 6. REGLAS DE VERIFICACIÓN APLICADAS

- Ninguna afirmación de este informe proviene de "lectura de intención": **los P0-1, P0-2, P0-4 y toda la tabla §1.3 se ejecutaron contra la BD real** con tokens de ADMIN y MOTORIZADO.
- No se ejecutó ninguna migración, no se borró ni insertó ningún dato permanente (los pedidos de prueba se eliminaron al finalizar).
