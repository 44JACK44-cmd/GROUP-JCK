# FASE 0 — ANÁLISIS DEL PROYECTO
## App de gestión de pedidos y reparto de gas (APK Android)

Fecha: 2026-11-13
Estado: Análisis completo — **pendiente de aprobación antes de iniciar Fase 1**

---

## 1. RESUMEN EJECUTIVO

Sistema de gestión para un negocio de distribución de balones de gas (y fierros/soportes retornables) compuesto por:

- **APK Android (Flutter)** — app móvil offline-first para el operador que atiende llamadas y para el repartidor en calle.
- **API REST (Spring Boot + Java + Spring Security + JWT)** — lógica de negocio, persistencia y seguridad.
- **MySQL** — base de datos relacional.

Principio rector: **simplicidad + velocidad + claridad + confiabilidad**. La app hace pocas cosas, pero muy bien.

---

## 2. ENTORNO DE DESARROLLO DETECTADO

| Componente | Estado |
|---|---|
| Flutter | ✅ 3.47.7 stable, Dart 3.13.5 |
| Android SDK | ✅ API 36, toolchain completo |
| JDK | ⚠️ Solo JDK 17 (Temurin). El spec pide Java 21 → instalar JDK 21 o usar Spring Boot 3.x con 17 (compatible). **DECISIÓN PENDIENTE** |
| MySQL | ❌ No instalado en esta máquina |
| Docker | ❌ No instalado |
| Visual Studio | ❌ (solo afecta a builds Windows, no a Android) |
| Directorio del proyecto | ✅ Vacío — greenfield |

**Implicancias:**
- Sin MySQL ni Docker locales: para desarrollo se necesita instalar MySQL (o Docker Desktop) **o** usar una base de datos remota (p. ej. MySQL en el VPS donde vivirá el backend).
- Spring Boot 3.x funciona con Java 17, por lo que no es bloqueante, pero se recomienda instalar JDK 21 para cumplir el spec.

---

## 3. ACTORES Y PERMISOS

### 3.1 Roles

| Acción | ADMINISTRADOR | REPARTIDOR |
|---|---|---|
| Crear/editar clientes y precios | ✅ | ❌ (solo lectura de los necesarios) |
| Crear pedidos | ✅ | ❌ (los pedidos los crea el operador/admin) |
| Gestionar productos | ✅ | ❌ |
| Asignar repartidor | ✅ | ❌ |
| Ver pedidos asignados | ✅ | ✅ |
| Navegar / llamar | ✅ | ✅ |
| Registrar entrega | ✅ | ✅ |
| Registrar pago | ✅ | ✅ |
| Registrar devolución de balón/fierro | ✅ | ✅ |
| Registrar combustible | ✅ | ✅ (gastos autorizados — alcance por confirmar) |
| Caja, gastos, reportes, usuarios | ✅ | ❌ |
| Control de balones (stock global) | ✅ | Solo su operación |

### 3.2 Notas
- Decisión tomada: **el ADMINISTRADOR atiende las llamadas**; no existe rol operador separado. Solo 2 roles: ADMINISTRADOR y REPARTIDOR.
- El repartidor solo puede registrar combustible como gasto; otros gastos los registra el admin.

---

## 4. REGLAS DEL NEGOCIO (RN)

### RN-1 Pedido
- Todo pedido referencia un **precio aplicado** que se congela al momento de crearlo. Cambios posteriores de precio del cliente **no** afectan pedidos históricos.
- Un pedido tiene un solo repartidor asignado y una sola dirección de entrega.
- Cantidad mínima: 1.

### RN-2 Estados del pedido
```
NUEVO → ASIGNADO → EN_CAMINO → ENTREGADO
  └──────────→ CANCELADO (desde cualquier estado no entregado)
```
- `ENTREGANDO` del spec se interpreta como parte del flujo EN_CAMINO→ENTREGADO (confirmación final en el punto de entrega). **DECISIÓN PENDIENTE:** ¿mantener 4 estados o simplificar a 3? Propuesta: mantener los 4 pero "ENTREGANDO" se marca automáticamente al abrir el detalle del pedido en reparto.
- Prohibido: doble entrega (un pedido ENTREGADO/CANCELADO no admite nuevas transiciones de entrega).
- Cancelación requiere motivo y queda en auditoría.

### RN-3 Balón (activo retornable)
- Cada entrega registra el estado del balón vacío: `RECIBIDO` / `NO_RECIBIDO` / `NO_APLICA`.
- `NO_RECIBIDO` genera un **saldo pendiente de devolución** por cliente (unidad: balón).
- Los fierros/soportes son un activo **separado**, con su propio saldo por cliente. Nunca se mezclan.
- Un cliente puede tener balones "en poder de él" = entregados − devueltos.

### RN-4 Pago
- Al confirmar entrega se indica: `PAGADO` / `PENDIENTE`.
- `PENDIENTE` genera deuda del cliente por el total del pedido.
- Los pagos se registran contra deuda/pedido; métodos: Efectivo, Yape, Plin, Transferencia, Otro.
- Regla anti-duplicado: no permitir registrar un pago que exceda la deuda pendiente del pedido/cliente sin confirmación explícita (sobrepago → queda como saldo a favor o se rechaza — **DECISIÓN PENDIENTE**).
- Un pago puede ser parcial (**DECISIÓN PENDIENTE**: ¿se permiten pagos parciales? Propuesta: sí, con saldo restante).

### RN-5 Caja
- Todo movimiento de dinero genera un `MovimientoCaja` automático:
  - Venta entregada+paga → ingreso (o al registrar pago, según criterio — ver §8).
  - Pago de deuda → ingreso.
  - Combustible/gasto → egreso.
- Apertura y cierre de caja por turno/día; el cierre muestra esperado vs. real.
- **DECISIÓN PENDIENTE:** ¿el ingreso por venta se registra al entregar (aunque quede pendiente de pago) o solo cuando se cobra? Propuesta: caja registra **cobros reales** (pagos), no ventas a crédito.

### RN-6 Combustible
- Registro por vehículo/repartidor: fecha, monto, kilometraje, observación. Genera egreso de caja.

### RN-7 Auditoría
- Toda operación crítica registra: usuario, fecha/hora, entidad, acción, valor anterior/nuevo cuando aplique (crear pedido, cambiar precio, asignar, entregar, pago, devolución, gasto, cancelación).

### RN-8 Offline
- El repartidor puede operar sin conexión: ver sus pedidos, fichas de cliente, navegar (GPS nativo), confirmar entrega/pago/devolución → se encolan y sincronizan al volver la red.
- Idempotencia: cada operación offline lleva un `client_uuid` único; el backend rechaza duplicados.
- El operador/admin requiere conexión para crear pedidos (o se encola igual — **DECISIÓN PENDIENTE**; propuesta: también offline-first, porque la llamada telefónica no espera).

---

## 5. FLUJOS PRINCIPALES

### 5.1 Flujo del pedido (operador)
```
Llamada → Buscar cliente (nombre/teléfono)
  ├─ Existe → ficha del cliente (precio auto, deuda, balones, ubicación, botón PEDIR BALÓN)
  └─ Nuevo → formulario mínimo (nombre, teléfono, dirección/referencia, ubicación en mapa, tipo)
→ Elegir producto (10/15/45 kg) — precio auto (personalizado o base)
→ Cantidad → Total
→ Forma de pago (efectivo/yape/plin/transferencia — solo informativa al crear)
→ Crear pedido → aparece en lista "NUEVO"
→ Asignar repartidor (o auto-asignación — DECISIÓN PENDIENTE)
```
Objetivo: **≤ 5 toques** desde que suena el teléfono hasta pedido creado.

### 5.2 Flujo de reparto (repartidor)
```
Login → "Tienes N entregas" (ordenadas por antigüedad)
→ Abrir pedido → datos cliente, llamar, navegar, detalle, total a cobrar
→ [ ENTREGAR PEDIDO ]
→ ¿Recibió balón vacío? SÍ/NO  (NO → pendiente devolución)
→ ¿Realizó el pago? SÍ/NO       (NO → deuda)
→ Confirmar → sync → siguiente entrega
```
Estados del pedido se actualizan: EN_CAMINO (al abrir/navegar), ENTREGADO (al confirmar).

### 5.3 Flujo de devolución de balones (fuera de entrega)
Cliente devuelve balones vacíos sin pedido → desde ficha del cliente o pantalla Balones → registrar movimiento `DEVOLUCION` → baja saldo pendiente.

### 5.4 Flujo de pagos / cobros
```
Cobros → lista de deudores (🔴 debe / 🟢 al día)
→ Ficha → pedidos pendientes con saldo
→ [ REGISTRAR PAGO ] → monto (editable, permite parcial), método, fecha
→ Genera MovimientoCaja ingreso + auditoría
```

### 5.5 Flujo de caja
```
Caja → Abrir caja (fondo inicial) → movimientos del día (auto + manuales)
→ Registrar gasto manual / combustible
→ Cierre: esperado (fondo + ingresos − egresos) vs. declarado → diferencia
```

---

## 6. MODELO DE DATOS PROPUESTO

### 6.1 Diagrama entidad-relación (resumen)

```
ROL 1───* USUARIO
USUARIO 1───* PEDIDO (creado_por, asignado_a)
USUARIO 1───* VEHICULO (opcional: repartidor_id)

CLIENTE 1───* DIRECCION_CLIENTE (entrega actual + historial de direcciones)
CLIENTE 1───* PRECIO_CLIENTE ──* PRODUCTO
PRODUCTO (independiente: nombre, capacidad_kg, precio_base, activo)

CLIENTE 1───* PEDIDO
PEDIDO 1───* DETALLE_PEDIDO ──* PRODUCTO   (cantidad, precio_unitario_aplicado)
PEDIDO 1───1 ENTREGA (balon_vacio: RECIBIDO/NO_RECIBIDO/NA; entregado_por, fecha)
PEDIDO 1───* PAGO (monto, método, fecha, registrado_por)
PEDIDO *───1 VEHICULO/USUARIO repartidor
PEDIDO *───1 CAJA (turno) opcional

BALON: modelado como SALDO, no como fila por unidad física.
  - MOVIMIENTO_BALON (cliente_id, tipo: ENTREGA/DEVOLUCION/NO_RECIBIDO,
    pedido_id, cantidad, fecha, usuario_id)
  - Saldo por cliente = Σ(ENTREGAS) − Σ(DEVOLUCIONES)
FIERRO: idéntico con MOVIMIENTO_FIERRO.

CAJA 1───* MOVIMIENTO_CAJA (tipo: INGRESO/EGRESO, origen: PAGO/GASTO/COMBUSTIBLE/APERTURA/CIERRE,
                             referencia_id, monto, fecha, usuario_id)
GASTO ──* MOVIMIENTO_CAJA
COMBUSTIBLE (vehiculo_id, fecha, monto, kilometraje, observacion) ──* MOVIMIENTO_CAJA

AUDITORIA (entidad, entidad_id, accion, usuario_id, fecha, detalle JSON)
```

### 6.2 Tablas (nombres en español, consistente con el dominio)

| Tabla | Campos clave |
|---|---|
| `rol` | id, nombre (ADMIN/REPARTIDOR/…) |
| `usuario` | id, nombre, telefono, email?, password_hash, rol_id, activo |
| `cliente` | id, nombre, telefono, tipo (PARTICULAR/RESTAURANTE/NEGOCIO/OTRO), direccion_actual, referencia, latitud, longitud, observaciones, deuda_total_cache?, activo, uuid_offline |
| `direccion_cliente` | id, cliente_id, direccion, referencia, lat, lng, es_principal, fecha |
| `producto` | id, nombre, capacidad_kg, precio_base, activo |
| `precio_cliente` | id, cliente_id, producto_id, precio, UNIQUE(cliente_id, producto_id) |
| `pedido` | id, numero (legible #1052), cliente_id, repartidor_id, estado, forma_pago, observaciones, total, creado_por, fecha, uuid_offline, version (control concurrencia) |
| `detalle_pedido` | id, pedido_id, producto_id, cantidad, precio_unitario |
| `entrega` | id, pedido_id UNIQUE, estado_balón_vacio, estado_pago, fecha, registrado_por, uuid_offline |
| `pago` | id, pedido_id NULLABLE (pago a deuda), cliente_id, monto, metodo, fecha, registrado_por, uuid_offline |
| `movimiento_balón` | id, cliente_id, tipo, pedido_id, cantidad, fecha, usuario_id |
| `movimiento_fierro` | (ídem) |
| `vehiculo` | id, nombre ("Moto 01"), placa?, activo |
| `caja` | id, fecha_apertura, fondo_inicial, estado (ABIERTA/CERRADA), cierre info |
| `movimiento_caja` | id, caja_id, tipo, origen, referencia_tipo/id, monto, fecha, usuario_id |
| `gasto` | id, descripcion, monto, categoria, fecha, usuario_id, movimiento_caja_id |
| `combustible` | id, vehiculo_id, fecha, monto, kilometraje, observacion, movimiento_caja_id |
| `auditoria` | id, entidad, entidad_id, accion, usuario_id, fecha, detalle_json |

**Notas de diseño:**
- `cliente.deuda_total_cache` es una **proyección** para lectura rápida; la fuente de verdad son los `pago`/`pedido` con saldo. Se recalcula en backend. Alternativa: vista SQL. Decidir en Fase 1.
- `uuid_offline` + constraint UNIQUE para idempotencia offline.
- `pedido.numero`: correlativo legible por día o global — **DECISIÓN PENDIENTE** (propuesta: correlativo global simple).
- Soft-delete (`activo`) en cliente/producto/usuario; pedidos nunca se borran, solo se cancelan.

---

## 7. ARQUITECTURA TÉCNICA

### 7.1 Backend — Spring Boot
```
src/main/java/com/grupojck/gas/
├── auth/            (JWT, login, filtro de seguridad, UserDetails)
├── cliente/         (controller, service, repository, dto)
├── producto/
├── pedido/          (máquina de estados, asignación, entrega, cancelación)
├── pago/
├── balon/           (movimientos, saldos por cliente)
├── fierro/
├── caja/            (apertura, cierre, movimientos)
├── combustible/
├── gasto/
├── auditoria/
├── sync/            (idempotencia offline: uuid_offline, version)
└── common/          (errores, validación, paginación, configuración)
```
- Spring Boot 3.x, Spring Security + JWT, Spring Data JPA, MySQL, Bean Validation, Maven/Gradle.
- Errores: `@ControllerAdvice` → respuestas JSON amigables; nunca stack traces al cliente.
- Fechas: `Instant`/UTC en BD, formato local en app.

### 7.2 Frontend — Flutter
```
lib/
├── main.dart
├── app/             (router, tema, DI)
├── core/            (network client, error handling, storage, sync engine, utils)
├── features/
│   ├── auth/        (login)
│   ├── home/        (dashboard de acciones)
│   ├── pedidos/     (lista, detalle, crear, asignar)
│   ├── clientes/    (lista, ficha, crear/editar, mapa)
│   ├── cobros/      (deudas, registrar pago)
│   ├── reparto/     (vista repartidor: entregas, confirmar)
│   ├── balones/     (stock, movimientos, saldos)
│   ├── caja/        (apertura, movimientos, cierre)
│   ├── combustible/
│   └── reportes/
├── shared/widgets/  (PrimaryButton, StatusBadge, OrderCard, EmptyState, LoadingState…)
└── shared/models/   (DTOs)
```
- **State management:** Riverpod (o Provider) — decisión a confirmar; propuesta **Riverpod** por idempotencia y testabilidad.
- **Navegación:** `go_router` con rutas por rol.
- **HTTP:** `dio` + interceptores (JWT, reintentos, detector offline).
- **Offline:** SQLite local (`drift` o `sqflite`) como cola de outbox + caché de lectura; sincronización al recuperar red.
- **Mapas:** `flutter_map` + OpenStreetMap (decidido: sin API key, gratis).
- **State management:** Riverpod. **Navegación:** go_router. **HTTP:** dio. **Offline DB:** drift (SQLite).
- **Ubicación:** `geolocator` + `geocoding` para "usar mi ubicación actual".

### 7.3 Comunicación
- HTTPS obligatorio en producción; JWT en header `Authorization: Bearer`.
- Base URL configurable por ambiente (dev: IP local / `10.0.2.2`; prod: dominio del VPS).
- **DECISIÓN PENDIENTE CRÍTICA:** ¿dónde se hostea el backend+MySQL? Opciones: VPS propio, Railway/Render, o servidor local del negocio. Esto define la URL y la estrategia offline.

---

## 8. ESTRATEGIA OFFLINE Y SINCRONIZACIÓN

### 8.1 Principios
- **Offline-first para el repartidor** (trabaja en la calle): pedidos asignados, clientes, precios, ubicaciones → caché local permanente (lectura).
- **Outbox pattern para escrituras:** toda operación (entrega, pago, devolución, combustible) se guarda primero en SQLite con `uuid_offline` y `estado=pendiente`, luego se envía al backend.
- El backend es la fuente de verdad; la app nunca decide lógica crítica sola (precios se resuelven en backend al sincronizar, aunque el precio aplicado ya viaja congelado en el pedido).

### 8.2 Flujo de sincronización
```
App detecta red → por cada item pendiente (FIFO, con reintentos exponenciales)
→ POST /api/sync/{operacion} con uuid_offline
→ Backend: si uuid ya existe → 200 "ya sincronizado" (idempotente)
→ App marca item como sincronizado → notificación "✓ Pedido actualizado"
```
- Conflictos: último-escritor-ganza por `version` del pedido; operaciones de entrega/pago son inmutables una vez confirmadas (no hay conflicto real: son eventos, no ediciones).
- Indicador persistente "📡 Sin conexión — se guardará y sincronizará" sin bloquear la UI.

### 8.3 Prevención de duplicados
- `uuid_offline` UNIQUE en: pedido, entrega, pago, movimiento_balón, movimiento_fierro, movimiento_caja.
- UI: botón de confirmar con estado "guardando…" para evitar doble-tap; deshabilitar tras primer tap.

---

## 9. NAVEGACIÓN Y PROPUESTA UX/UI

### 9.1 Estructura
```
Login (por rol)
└── Shell con bottom nav (5 items máx):
    🏠 Inicio   📦 Pedidos   👥 Clientes   💰 Cobros   ☰ Más
    "Más": 🛢️ Balones · ⛽ Combustible · 💵 Caja · 📊 Reportes · ⚙️ Configuración
```
- **Repartidor**: login directo a su pantalla de entregas ("Buenos días, Carlos — Tienes N entregas"). Bottom nav reducido: Entregas · Clientes · Caja(movimientos propios) · Perfil.
- El botón "NUEVO PEDIDO" del Home abre un **flujo de una sola pantalla con pasos internos** (stepper horizontal o una sola página con secciones), no 5 pantallas.

### 9.2 Principios UX aplicados del spec
- Lenguaje cotidiano ("Cobrar S/45", "Balón por devolver"), no técnico.
- Colores semánticos: 🟡 pendiente · 🔵 asignado/en camino · 🟢 entregado/pagado · 🔴 deuda/error/cancelado · ⚪ neutro.
- Botones ≥ 48dp, targets táctiles grandes, un color primario sobrio (propuesta: azul/verde petróleo sobrio — definir en diseño).
- Estados vacíos con mensaje humano ("No tienes pedidos pendientes. Cuando llegue uno, aparecerá aquí.").
- Errores en lenguaje simple + detalle técnico solo en logs.
- Confirmaciones solo en acciones destructivas (cancelar pedido, cerrar caja).

### 9.3 Componentes reutilizables
`PrimaryButton`, `SecondaryButton`, `StatusBadge`, `OrderCard`, `CustomerCard`, `PaymentCard`, `BallStatusCard`, `EmptyState`, `LoadingState`/skeleton, `DebtBadge`, `SyncBanner`.

---

## 10. API — ENDPOINTS PROPUESTOS (v1)

```
# Auth
POST /api/auth/login                      { telefono/email, password } → JWT
POST /api/auth/refresh
GET  /api/auth/me

# Clientes
GET    /api/clientes?q=&tipo=&page=       (búsqueda + paginación)
POST   /api/clientes
GET    /api/clientes/{id}                 (ficha completa: deuda, balones, historial)
PUT    /api/clientes/{id}
GET    /api/clientes/{id}/historial
GET    /api/clientes/{id}/saldo-balones
POST   /api/clientes/{id}/ubicacion       (actualizar lat/lng/referencia)

# Productos y precios
GET    /api/productos
POST   /api/productos                      (admin)
PUT    /api/productos/{id}
GET    /api/clientes/{id}/precios
PUT    /api/clientes/{id}/precios          (upsert precio personalizado)

# Pedidos
GET    /api/pedidos?estado=&fecha=&repartidor=
POST   /api/pedidos                        (admite uuid_offline)
GET    /api/pedidos/{id}
PUT    /api/pedidos/{id}                   (solo campos editables en estado NUEVO)
POST   /api/pedidos/{id}/asignar           { repartidor_id }
POST   /api/pedidos/{id}/iniciar-reparto   → EN_CAMINO
POST   /api/pedidos/{id}/entregar          { balon_vacio, pago_realizado, uuid_offline }
POST   /api/pedidos/{id}/cancelar          { motivo }

# Pagos
GET    /api/pagos?cliente=&desde=&hasta=
POST   /api/pagos                          { pedido_id?, cliente_id, monto, metodo, uuid_offline }

# Balones y fierros
GET    /api/balones                        (stock global: llenos/vacíos/en clientes/pendientes)
GET    /api/balones/clientes/{id}          (saldo por cliente)
POST   /api/balones/movimientos            { cliente_id, tipo, cantidad, uuid_offline }
GET    /api/fierros  (ídem)

# Caja
GET    /api/caja/actual
POST   /api/caja/apertura                  { fondo_inicial }
POST   /api/caja/movimientos               { tipo, monto, descripcion } (manual)
POST   /api/caja/cierre                    { monto_declarado }
GET    /api/caja/{id}/movimientos

# Combustible y gastos
GET/POST /api/combustible
GET/POST /api/gastos

# Reportes
GET    /api/reportes/resumen?desde=&hasta=  (pedidos, ventas, cobrado, pendiente, combustible, balones)

# Sync
POST   /api/sync/lote                       (recibe cola de operaciones offline, devuelve resultados por item)
```

---

## 11. REQUISITOS NO FUNCIONALES

| Categoría | Requisito |
|---|---|
| Rendimiento | Listados paginados; respuesta API < 500 ms en operaciones comunes; app usable en gama baja |
| Offline | Repartidor 100% funcional en entrega sin red; operador degrada con aviso claro |
| Seguridad | JWT + expiración + refresh; contraseñas con BCrypt; roles en backend (nunca solo en UI); HTTPS; validación servidor obligatoria |
| Confiabilidad | Idempotencia en todas las escrituras offline; transiciones de estado atómicas (evitar doble entrega en concurrencia → constraint + version check) |
| Usabilidad | Tarea "nuevo pedido" ≤ 5 toques; textos en español, lenguaje cotidiano; legible a luz solar (contraste) |
| Mantenibilidad | Capas claras; sin lógica de negocio en widgets; DTOs estables |
| Compatibilidad | Android 8+ (API 26+) razonable; portrait primero, landscape no roto |
| Auditoría | Trazabilidad completa de operaciones de dinero y balones |

---

## 12. RIESGOS TÉCNICOS

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Dónde hostear backend+MySQL (no hay servidor definido) | **Alto** | Resolver antes de Fase 1; definir URL de API y estrategia de deploy |
| Java 21 no instalado (solo 17) | Bajo | Instalar JDK 21 o usar Boot 3.x con 17 |
| MySQL no instalado localmente | Medio | Instalar MySQL/Docker o apuntar a MySQL remoto del VPS |
| Offline + pagos concurrentes | Medio | Idempotencia por uuid; estados inmutables post-entrega |
| Mapas: Google Maps requiere API key/facturación | Bajo | Usar flutter_map + OSM por defecto |
| Doble entrega por dos dispositivos | Medio | Constraint UNIQUE(pedido_id) en entrega + chequeo de estado transaccional |
| Deuda/cache desincronizada | Medio | Deuda calculada desde pagos en backend; cache solo para lectura con recálculo |
| Alcance: fierros, multi-vehículo, multi-sucursal | Futuro | Modelo ya los contempla sin sobre-ingeniería ahora |

---

## 13. DECISIONES

### Resueltas (2026-11-13)
- ✅ **Rol operador**: el ADMINISTRADOR atiende las llamadas. Solo 2 roles: ADMINISTRADOR y REPARTIDOR.
- ✅ **Base de datos**: MySQL instalado localmente en esta PC para desarrollo.
- ✅ **Mapas**: OpenStreetMap (`flutter_map` + `latlong2`), sin API key.
- ⏳ **Backend hosting**: aún no decidido → se desarrolla contra `localhost`/IP local; la URL de producción quedará como variable de entorno configurable (`API_BASE_URL`). Recomendación para producción: VPS con dominio + HTTPS (costo bajo) o Render/Railway para el API + MySQL gestionado.

### Pendientes menores (se asumirán los valores propuestos salvo indicación contraria)
1. **Java**: instalar JDK 21 (recomendado, cumple spec).
2. **Pagos parciales**: permitidos, con saldo restante.
3. **Sobrepago**: rechazado con mensaje claro.
4. **Numeración de pedidos**: correlativo global (#1, #2, …).
5. **Caja**: registra cobros reales (pagos), no ventas a crédito.
6. **Gastos del repartidor**: solo combustible; otros gastos los registra el admin.
7. **Asignación**: manual por el admin en v1.
8. **Moneda**: soles (S/).
9. **Fierros**: solo control de saldo retornable (sin cobro).
10. **State management Flutter**: Riverpod. Navegación: go_router. HTTP: dio. Offline DB: drift (SQLite).

---

## 14. PLAN DE IMPLEMENTACIÓN POR FASES (ajustado del spec)

| Fase | Contenido | Entregable / Criterio de salida |
|---|---|---|
| **0** | Este documento | ✅ Análisis aprobado + decisiones pendientes resueltas |
| **1 — Esqueleto** | `flutter create`, proyecto Spring Boot, config MySQL, JWT login, tema, navegación base, CI de compilación | APK "hola mundo" con login funcional contra API real |
| **2 — Clientes** | CRUD, búsqueda, ficha con deuda/balones/historial, ubicación en mapa | Cliente creado en < 1 min desde la app |
| **3 — Pedidos** | Productos, precios personalizados, creación rápida, estados, asignación | Pedido creado en ≤ 5 toques; precio correcto siempre |
| **4 — Repartos** | Vista repartidor, navegar, entrega con balón/pago, cobro | Repartidor completa una entrega real sin papel |
| **5 — Balones y fierros** | Stock, movimientos, saldos por cliente | Saldo de balones correcto por cliente |
| **6 — Caja y cobros** | Pagos, deudas, apertura/cierre caja, gastos, combustible | Cierre de caja cuadra con movimientos |
| **7 — Offline** | SQLite outbox, caché repartidor, sync idempotente | Reparto completo en modo avión + sync sin duplicados |
| **8 — Reportes** | Resumen día/semana/mes, deudas, balones | Reporte del día en una pantalla |
| **9 — Calidad** | Tests (unit + widget + API), revisión UX, seguridad, build APK release | APK firmada lista para producción |

**Orden recomendado real:** Fases 1→3 primero en backend+app (el corazón del negocio es pedido→entrega→cobro). Offline (Fase 7) puede adelantarse parcialmente en Fase 4 si el repartidor lo necesita antes.

---

## 15. ESTRUCTURA INICIAL DEL PROYECTO (a crear en Fase 1)

```
GROUP JCK/
├── docs/
│   └── FASE0_ANALISIS.md          ← este archivo
├── backend/                        ← Spring Boot (Java 21)
│   ├── pom.xml / build.gradle
│   └── src/main/.../gas/
├── app/                            ← Flutter (APK)
│   ├── pubspec.yaml
│   └── lib/
└── README.md                       ← cómo levantar todo
```

---

## 16. PRÓXIMO PASO

Aprobar este análisis y responder las **Decisiones Pendientes (§13)** — especialmente hosting del backend y rol del operador — para iniciar la **Fase 1 (Esqueleto)**.
