-- PASO 10 — Fierro y balón vacío: un solo concepto comercial
--
-- Regla de negocio:
--   * El FIERRO (soporte) y el BALÓN VACÍO son el MISMO activo retornable:
--     se controlan por saldo (movimiento_bal_on / movimiento_fierro) y NUNCA
--     se cobran ni generan dinero.
--   * En el catálogo existen UNA sola vez, marcados tipo = 'RETORNABLE',
--     con precio 0. No aparecen en la lista de productos que se venden.
--
-- Esta migración es NO destructiva:
--   * No borra productos ni pedidos.
--   * Los productos duplicados solo se marcan `activo = false`; siguen
--     existiendo y las entregas históricas que los usan se siguen viendo.
--   * El índice único solo cubre los productos ACTIVOS.
--
-- Reejecutable: se puede correr las veces que haga falta.

-- 1) Tipo de producto: vendible o activo retornable.
alter table public.productos
  add column if not exists tipo text not null default 'PRODUCTO';

-- 2) Solo dos valores posibles.
alter table public.productos
  drop constraint if exists productos_tipo_check;

alter table public.productos
  add constraint productos_tipo_check
  check (tipo in ('PRODUCTO', 'RETORNABLE'));

-- 3) Un activo retornable nunca tiene precio (no se cobra).
--    NOT VALID: no revisa filas antiguas, pero sí bloquea las nuevas.
alter table public.productos
  drop constraint if exists productos_retornable_sin_precio;

alter table public.productos
  add constraint productos_retornable_sin_precio
  check (tipo <> 'RETORNABLE' or precio_base = 0) not valid;

-- 4) Depurar duplicados sin borrar nada: en cada grupo con el mismo nombre se
--    conserva UNA fila activa (la que ya está usada en pedidos, si hay varias;
--    si no, la de id menor) y las demás quedan `activo = false`.
update public.productos p
set activo = false
where p.activo
  and p.id <> (
    select q.id
    from public.productos q
    where q.empresa_id = p.empresa_id
      and q.activo
      and lower(btrim(q.nombre)) = lower(btrim(p.nombre))
    order by
      case
        when exists (
          select 1 from public.detalle_pedido d where d.producto_id = q.id
        ) then 0
        else 1
      end,
      q.id
    limit 1
  );

-- 5) A partir de ahora no se puede repetir un nombre activo en la misma empresa.
create unique index if not exists ux_productos_empresa_nombre_activo
  on public.productos (empresa_id, lower(btrim(nombre)))
  where activo;

-- 6) Crear el concepto único "Fierro / Balón vacío" para cada empresa que aún
--    no lo tenga. precio_base = 0 y tipo RETORNABLE: jamás genera dinero.
insert into public.productos
  (empresa_id, nombre, capacidad_kg, precio_base, descripcion, tipo, activo)
select
  e.id,
  'Fierro / Balón vacío',
  null,
  0,
  'Activo retornable. El fierro (soporte) y el balón vacío son el mismo concepto: se controlan por saldo y no se cobran.',
  'RETORNABLE',
  true
from public.empresas e
where not exists (
  select 1
  from public.productos p
  where p.empresa_id = e.id
    and p.activo
    and lower(btrim(p.nombre)) = lower('Fierro / Balón vacío')
);
