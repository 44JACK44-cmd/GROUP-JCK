-- PASO 11 — Cuaderno digital del motorizado
--
-- Problema que corrige:
--   El motorizado puede REGISTRAR un pedido cuando recepción se olvidó de
--   anotarlo, pero las políticas RLS solo dejaban insertar al ADMIN. La app
--   fallaba con "no tienes permiso" (42501) y el pedido se perdía.
--
-- Qué permite (y nada más):
--   * Crear un cliente de su propia empresa.
--   * Crear un pedido marcado `origen = 'MOTORIZADO'`, estado NUEVO y
--     `creado_por` = el propio motorizado.
--   * Insertar las líneas de ESE pedido.
--
-- Qué NO permite:
--   * Crear pedidos como si fueran de recepción (`origen = 'ADMIN'`).
--   * Tocar pedidos de otra empresa (siempre `empresa_id = mi_empresa()`).
--   * Crear pedidos a nombre de otro usuario.
--
-- Reejecutable y no destructivo.

-- 1) Clientes: cualquier usuario autenticado de la empresa puede registrar uno
--    nuevo (el motorizado ya puede leer todos los de su empresa).
drop policy if exists "clientes_moto_insert" on public.clientes;
create policy "clientes_moto_insert" on public.clientes
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and auth.uid() is not null
  );

-- 2) Pedidos: el motorizado solo puede crear su propio cuaderno.
drop policy if exists "pedidos_moto_insert" on public.pedidos;
create policy "pedidos_moto_insert" on public.pedidos
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and origen = 'MOTORIZADO'
    and estado = 'NUEVO'
    and creado_por = auth.uid()
  );

-- 3) Líneas del pedido: solo para pedidos creados por ese motorizado.
drop policy if exists "detalle_moto_insert" on public.detalle_pedido;
create policy "detalle_moto_insert" on public.detalle_pedido
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and exists (
      select 1
        from public.pedidos p
       where p.id = detalle_pedido.pedido_id
         and p.empresa_id = detalle_pedido.empresa_id
         and p.origen = 'MOTORIZADO'
         and p.creado_por = auth.uid()
    )
  );
