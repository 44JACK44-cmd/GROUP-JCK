# FASE 6 — Cómo aplicar los pasos 10 y 11 (guía paso a paso)

Estado a hoy: los pasos **1 a 9** ya están aplicados en la base real.
Faltan **10** y **11**. Los dos son seguros: no borran datos y se pueden
ejecutar más de una vez sin romper nada.

Todo se hace desde el navegador, en **Supabase → SQL Editor**. No hace falta
instalar nada ni usar la terminal.

---

## Antes de empezar (2 minutos)

1. Abre <https://supabase.com/dashboard> y entra al proyecto
   `kzhvutzkggcgrnalpcqs`.
2. Menú izquierdo → **SQL Editor** → botón **New query**.
3. Ten a mano los archivos del repositorio:
   - `supabase/steps/v7_10_productos.sql`
   - `supabase/steps/v7_11_cuaderno_motorizado.sql`
   - `supabase/steps/99_verificar.sql`

> Consejo: abre cada archivo en el Bloc de notas (o en VS Code), copia **todo**
> el contenido y pégalo en la consulta. El archivo ya viene preparado para
> ejecutarse completo de una sola vez.

---

## Paso 10 — `v7_10_productos.sql`

**Qué arregla**

- El catálogo hoy tiene **3 pares de productos duplicados**. Este paso deja un
  solo registro activo por nombre y **no borra nada**: los sobrantes quedan
  como `activo = false`, así que los pedidos viejos que los usan se siguen
  viendo igual.
- Crea el concepto único **"Fierro / Balón vacío"** (`tipo = RETORNABLE`,
  precio 0) para cada empresa: el fierro (soporte) y el balón vacío son el
  mismo activo y **nunca generan dinero**.
- Agrega la columna `productos.tipo` y un índice que impide volver a duplicar
  un nombre activo.

**Cómo ejecutarlo**

1. En el SQL Editor, pega el contenido completo de `v7_10_productos.sql`.
2. Pulsa **Run** (o `Ctrl + Enter`).
3. Debe aparecer **"Success. No rows returned"**.

**Si sale un error**

| Mensaje | Qué significa | Qué hacer |
|---|---|---|
| `duplicate key value violates unique constraint "ux_productos_empresa_nombre_activo"` | Quedaron dos productos activos con el mismo nombre (con mayúsculas o espacios distintos). | Ejecuta otra vez el archivo completo: la limpieza de duplicados corre antes de crear el índice y lo resuelve. |
| `column "tipo" ... already exists` | Ya estaba aplicado. | Ignóralo, el paso es reejecutable; sigue con el 11. |
| `permission denied` | Estás en la organización equivocada o con un rol de solo lectura. | Entra con la cuenta dueña del proyecto. |

---

## Paso 11 — `v7_11_cuaderno_motorizado.sql`

**Qué arregla**

Hoy, si recepción olvida anotar un pedido, el motorizado **no puede**
registrarlo desde el teléfono: la base lo rechaza con un error de permisos.
Este paso le permite exactamente tres cosas y nada más:

1. Crear un cliente de su propia empresa.
2. Crear un pedido marcado `origen = 'MOTORIZADO'`, estado `NUEVO` y
   `creado_por` = él mismo.
3. Insertar las líneas de **ese** pedido.

No puede crear pedidos como si fueran de recepción, ni tocar datos de otra
empresa, ni crear pedidos a nombre de otra persona.

**Cómo ejecutarlo**

1. **New query** → pega el contenido completo de `v7_11_cuaderno_motorizado.sql`.
2. **Run**.
3. Debe aparecer **"Success. No rows returned"**.

Es normal que no devuelva filas: solo crea permisos.

---

## Verificación final — `99_verificar.sql`

1. **New query** → pega `99_verificar.sql` → **Run**.
2. Debe devolver una tabla de **22 filas**, todas con resultado **`OK`**.

Las dos nuevas, que hoy salen en `FALTA`, son:

| Control | Qué confirma |
|---|---|
| `permiso pedido del motorizado` | El motorizado puede registrar su propio pedido |
| `permiso lineas del motorizado` | Puede guardar los productos de ese pedido |
| `permiso cliente del motorizado` | Puede crear el cliente nuevo desde la calle |

(El total incluye las 19 verificaciones anteriores, que ya estaban en `OK`.)

### Si alguna fila sale `FALTA`

| Fila en `FALTA` | Qué volver a ejecutar |
|---|---|
| `columna productos.tipo`, `indice unico producto activo`, `concepto fierro/balon vacio` | Paso 10 completo |
| `permiso pedido del motorizado`, `permiso lineas del motorizado`, `permiso cliente del motorizado` | Paso 11 completo |
| Cualquier otra (triggers, funciones, columnas de pasos 1–9) | El paso correspondiente de `supabase/steps/00_LEEME.md` |

---

## Qué cambia en la app cuando estén aplicados

- **Catálogo (`/balones`, `/pedidos/nuevo`)**: un solo "Fierro / Balón vacío",
  sin duplicados y sin precio. No aparece entre los productos que se venden.
- **Motorizado → Mi registro → Pedido**: el pedido se guarda en el servidor en
  lugar de mostrar "aún no está habilitado".
- **Caja y rendición**: los saldos de fierros y balones dejan de mezclarse con
  el dinero (el concepto retornable ya no se cuenta como venta).

Mientras no estén aplicados, la app **no se rompe**: avisa con un mensaje claro
y sigue funcionando con lo que hay.

---

## Si algo sale mal (plan de vuelta atrás)

Ninguno de los dos pasos borra datos, así que no hace falta restaurar nada. Si
quisieras deshacer el paso 10 por completo:

```sql
drop index if exists public.ux_productos_empresa_nombre_activo;
alter table public.productos drop constraint if exists productos_retornable_sin_precio;
alter table public.productos drop constraint if exists productos_tipo_check;
alter table public.productos drop column if exists tipo;
-- Los productos desactivados siguen ahí: se reactivan a mano si hiciera falta.
```

Para el paso 11 basta con eliminar los tres permisos:

```sql
drop policy if exists "pedidos_moto_insert" on public.pedidos;
drop policy if exists "detalle_moto_insert" on public.detalle_pedido;
drop policy if exists "clientes_moto_insert" on public.clientes;
```

---

## Después de aplicar

1. Abre la app con el usuario **ADMIN** → revisa que el catálogo no tenga
   duplicados.
2. Abre con el **MOTORIZADO** → Mi registro → Pedido → registra uno de prueba.
3. Bórralo desde el detalle como admin (o márcalo como no entregado).
4. Tira hacia abajo en **Caja** y **Rendición** para confirmar que los números
   se actualizan.

Detalle técnico de cada paso: `supabase/steps/00_LEEME.md`.
