# Diagnóstico del flujo operativo de pedidos

Proyecto: GROUP JCK — GasApp (Flutter/Android + Supabase)
Fecha: 2026-11-13
Base de datos inspeccionada: `kzhvutzkggcgrnalpcqs` (proyecto `group-jck-gas`)

---

## 1. Estado real del proyecto (inspección)

### Lo que YA existe y NO se toca

| Módulo | Ubicación | Estado |
|---|---|---|
| Supabase init + config | `app/lib/core/config.dart` | Funciona (anon key, sin `service_role` en el APK) |
| Auth (login por teléfono/correo) | `app/lib/features/auth/` | Funciona. `resolver-login` edge function resuelve admin por correo real |
| Perfiles + roles | `auth_controller.dart` + tabla `perfiles` | Funciona. `empresa_id` se deriva del perfil del usuario |
| Multi-empresa + RLS | `supabase/schema.sql` | Funciona. `mi_empresa()`, `es_admin()` con `security definer` |
| Outbox offline | `app/lib/core/offline/outbox.dart` | Funciona (con bugs, ver §4) |
| Módulos admin | clientes, motorizados, caja, cobros, combustible, reportes, balones | Funcionan (lectura/registro básico) |
| Actualización OTA | `core/update/app_update_service.dart` | Funciona |

### Tablas existentes (confirmadas contra la BD real)

`empresas`, `perfiles`, `clientes`, `direcciones_cliente`, `productos`, `precios_cliente`,
`pedidos`, `detalle_pedido`, `entregas`, `pagos`, `movimiento_bal_on`, `movimiento_fierro`,
`vehiculos`, `cajas`, `movimiento_caja`, `gastos`, `combustible`, `auditoria`, `app_versiones`.

La BD tiene 3 empresas (Grupo JCK, Grupo Gas, choke) y 5 perfiles, pero **0 clientes y 0 pedidos**.

---

## 2. CAUSA RAÍZ — el ADMIN no puede registrar pedidos

Reproducido contra la BD real con el token del admin (`admin@grupojck.app`):

```
POST /rest/v1/pedidos        → 200 OK  (se crea el pedido)
POST /rest/v1/detalle_pedido → 42501 "new row violates row-level security policy
                                        for table detalle_pedido"
```

**Causa:** `app/lib/features/pedidos/nuevo_pedido_page.dart` (líneas 210-215) inserta la cabecera
del pedido **con** `empresa_id`, pero las líneas de detalle **sin** `empresa_id`:

```dart
final insertado = await _sb.from('pedidos').insert(pedido).select('id').single();
for (final d in detalles) {
  await _sb.from('detalle_pedido').insert({...d, 'pedido_id': pedidoId}); // ← falta empresa_id
}
```

La política `detalle_admin` exige `empresa_id = public.mi_empresa()` y la columna es `NOT NULL`
(`migration_empresa.sql`), por eso el insert se rechaza.

**Efecto en cadena (por eso el ADMIN "no puede registrar pedidos"):**

1. Se crea el **pedido huérfano** (sin productos, con `total` ya calculado).
2. El `catch` genérico interpreta el error de RLS como "sin internet" y encola al Outbox
   mostrando *"Sin conexión: pedido guardado"*.
3. Al sincronizar, `_insertarPedido` vuelve a insertar la cabecera → viola `uuid_offline` (único)
   → la operación queda **atascada en la cola para siempre** y cada reintento falla igual.
4. El pedido huérfano queda visible en la lista: total correcto pero **sin productos**.

---

## 3. Otros defectos verificados

| # | Defecto | Evidencia | Impacto |
|---|---|---|---|
| D1 | `detalle_pedido` sin `empresa_id` | 42501 | **Pedidos sin productos** (causa raíz) |
| D2 | `forma_pago='DEUDA'` viola check | 23514 | No se puede registrar "queda debiendo" |
| D3 | Outbox reintenta cabecera ya insertada | 23505 en sync | Cola offline trabada, pedidos duplicados |
| D4 | Entrega no guarda monto cobrado ni método | `entregas` sólo tiene `estado_pago` | No se sabe cuánto cobró ni si fue Yape |
| D5 | Sin deuda por pedido | No existe saldo | Impossible saber "quién debe qué" |
| D6 | `estado_bal_on_vacio` no genera "vacío pendiente" | No se registra devolución | Balones pendientes invisibles |
| D7 | Motorizado ve pedidos **sin asignar** | RLS `repartidor_id is null` | "Mis pedidos" mezcla pedidos de otros |
| D8 | Sin `motivo_cancelacion` | — | Cancelación sin motivo |
| D9 | Sin auditoría de cambios | `auditoria` no se escribe | Sin trazabilidad |
| D10 | `pagos` no alimentan la caja | `movimiento_caja` solo manual/combustible | Caja descuadrada vs. cobros |
| D11 | Sin prioridad por antigüedad | Listas ordenan por `fecha desc` | Los más antiguos de últimos |
| D12 | Ubicación: sólo GPS del propio admin | `cliente_form_page` usa `getCurrentPosition()` | Se confunde "mi ubicación" con "ubicación del cliente" |

---

## 4. Decisiones de diseño (para no romper lo existente)

1. **No se reescribe la app.** Se respetan tablas, RLS, edge functions, outbox, tema y módulos
   existentes. Se añaden repositorios (`app/lib/core/data/`) y se migran las pantallas a ellos.
2. **La BD solo crece, no se duplica.** No se crean tablas nuevas: `entregas`, `pagos`,
   `movimiento_bal_on`, `movimiento_fierro`, `auditoria` y `movimiento_caja` ya cubren el modelo.
3. **Los datos derivados no se almacenan.** Deuda, saldo de balones, prioridad y antigüedad se
   calculan desde los registros reales (fuente de verdad única, sin desincronización).
4. **La ubicación siempre es la del CLIENTE.** `cliente.latitud/longitud`. La ubicación del
   teléfono sirve solo para *origen* de la ruta, nunca como destino.
5. **Transiciones de estado controladas** por un único módulo (`core/domain/estado_pedido.dart`).
6. **Migración DB mínima y segura** (`supabase/migration_v3.sql`): dos CHECK ampliados, índices,
   trigger de caja y trigger de estado. Todo `if not exists` / `drop ... if exists` → reejecutable.
7. **El APK nunca lleva `service_role`.** Las operaciones privilegiadas siguen en Edge Functions.

---

## 5. Mapa de la solución por fases

| Fase | Entrega |
|---|---|
| 1 | Corregir creación de pedidos por ADMIN (D1, D3) + núcleo de dominio |
| 2 | Cliente: dirección, referencia, coordenadas, mapa (D12) |
| 3 | Asignación, "Mis pedidos", prioridad por antigüedad (D7, D11) |
| 4 | Entrega del motorizado (D4, D8) |
| 5 | Pagos, Yape, deudas (D5) |
| 6 | Balones vacíos y pendientes, fierros (D6) |
| 7 | Historial de pedidos |
| 8 | Rendición del ADMIN |
| 9 | Caja e informes (D10) |
| 10 | Pruebas, auditoría, realtime, validaciones (D9) |
