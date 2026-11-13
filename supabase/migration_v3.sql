-- ============================================================
-- MIGRACIÓN v3 — Flujo operativo de pedidos (Grupo JCK)
--
-- Qué resuelve:
--  1. Permite registrar pedidos con forma de pago "DEUDA" (crédito).
--  2. Permite el estado "NO_ENTREGADO".
--  3. Permite el estado de pago "PARCIAL" en entregas.
--  4. Trigger: al registrar una entrega, el pedido queda ENTREGADO
--     (red de seguridad, también para la sincronización offline).
--  5. Trigger: cada cobro genera el ingreso en caja (caja y cobros
--     quedan integrados, sin duplicar sistemas).
--  6. Guard de transiciones: un pedido ENTREGADO o CANCELADO no puede
--     cambiar de estado salvo por una operación administrativa explícita.
--  7. Función `reactivar_pedido` (solo ADMIN de su empresa).
--  8. Índices para consultas eficientes (pendientes, rendición, deudas).
--  9. Realtime: `pedidos` entra en la publicación para que el admin y el
--     motorizado vean los cambios sin cerrar la app.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor → New query
-- Es REEJECUTABLE: no rompe nada si se ejecuta dos veces.
-- NO destructivo: no borra datos.
-- ============================================================

-- ---------- 1. Forma de pago "DEUDA" (queda debiendo) ----------
do $$
begin
  if exists (
    select 1 from pg_constraint where conname = 'pedidos_forma_pago_check'
  ) then
    alter table public.pedidos drop constraint pedidos_forma_pago_check;
  end if;
end $$;

alter table public.pedidos
  add constraint pedidos_forma_pago_check
  check (forma_pago in ('EFECTIVO', 'YAPE', 'PLIN', 'TRANSFERENCIA', 'OTRO', 'DEUDA'));

-- ---------- 2. Estado "NO_ENTREGADO" ----------
do $$
begin
  if exists (
    select 1 from pg_constraint where conname = 'pedidos_estado_check'
  ) then
    alter table public.pedidos drop constraint pedidos_estado_check;
  end if;
end $$;

alter table public.pedidos
  add constraint pedidos_estado_check
  check (estado in ('NUEVO', 'ASIGNADO', 'EN_CAMINO', 'ENTREGADO', 'CANCELADO', 'NO_ENTREGADO'));

-- ---------- 3. Pago parcial en entregas ----------
do $$
begin
  if exists (
    select 1 from pg_constraint where conname = 'entregas_estado_pago_check'
  ) then
    alter table public.entregas drop constraint entregas_estado_pago_check;
  end if;
end $$;

alter table public.entregas
  add constraint entregas_estado_pago_check
  check (estado_pago in ('PAGADO', 'PARCIAL', 'PENDIENTE'));

-- ---------- 4. Entrega ⇒ el pedido queda ENTREGADO ----------
create or replace function public.trg_entrega_pedido_estado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.pedidos
     set estado = case when new.estado_pago = 'PAGADO' then 'ENTREGADO' else 'ENTREGADO' end
   where id = new.pedido_id
     and empresa_id = new.empresa_id
     and estado in ('NUEVO', 'ASIGNADO', 'EN_CAMINO', 'NO_ENTREGADO');
  return new;
end $$;

drop trigger if exists trg_entrega_pedido_estado on public.entregas;
create trigger trg_entrega_pedido_estado
  after insert on public.entregas
  for each row execute function public.trg_entrega_pedido_estado();

-- ---------- 5. Cobro ⇒ ingreso en caja ----------
-- Los cobros de los motorizados entran solos a la caja abierta.
-- SECURITY DEFINER para que el motorizado no necesite permiso de escritura
-- en movimiento_caja (el aislamiento por empresa_id no se altera).
create or replace function public.trg_pago_ingreso_caja()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caja uuid;
begin
  select id into v_caja
    from public.cajas
   where empresa_id = new.empresa_id
     and estado = 'ABIERTA'
   order by fecha_apertura desc
   limit 1;

  if v_caja is not null then
    insert into public.movimiento_caja
      (empresa_id, caja_id, tipo, origen, referencia_id, monto, descripcion, usuario_id)
    values
      (new.empresa_id, v_caja, 'INGRESO', 'PAGO', new.id, new.monto,
       'Cobro de pedido', new.registrado_por);
  end if;
  return new;
end $$;

drop trigger if exists trg_pago_ingreso_caja on public.pagos;
create trigger trg_pago_ingreso_caja
  after insert on public.pagos
  for each row execute function public.trg_pago_ingreso_caja();

-- ---------- 6. Guard de transiciones de estado ----------
-- Un pedido ENTREGADO o CANCELADO es terminal. Solo la función
-- `reactivar_pedido` (administración explícita) puede reabrirlo.
create or replace function public.trg_pedidos_guarda_estado()
returns trigger
language plpgsql
as $$
begin
  if old.estado is distinct from new.estado
     and old.estado in ('ENTREGADO', 'CANCELADO')
     and coalesce(current_setting('app.allow_reopen', true), '0') <> '1' then
    raise exception 'Transición no permitida: % → %', old.estado, new.estado
      using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists trg_pedidos_guarda_estado on public.pedidos;
create trigger trg_pedidos_guarda_estado
  before update on public.pedidos
  for each row execute function public.trg_pedidos_guarda_estado();

-- ---------- 7. Reactivar pedido (solo ADMIN de su empresa) ----------
create or replace function public.reactivar_pedido(p_pedido_id uuid, p_motivo text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid := public.mi_empresa();
  v_rol text := public.mi_rol();
  v_estado text;
begin
  if v_empresa is null then
    raise exception 'Sin empresa asociada' using errcode = 'P0001';
  end if;
  if v_rol <> 'ADMIN' then
    raise exception 'Solo un administrador puede reactivar un pedido' using errcode = '42501';
  end if;

  select estado into v_estado
    from public.pedidos
   where id = p_pedido_id and empresa_id = v_empresa;

  if v_estado is null then
    raise exception 'El pedido no existe' using errcode = 'P0001';
  end if;
  if v_estado not in ('CANCELADO', 'ENTREGADO', 'NO_ENTREGADO') then
    raise exception 'Este pedido no se puede reactivar' using errcode = 'P0001';
  end if;

  perform set_config('app.allow_reopen', '1', true);
  update public.pedidos
     set estado = 'NUEVO'
   where id = p_pedido_id and empresa_id = v_empresa;
  perform set_config('app.allow_reopen', '0', true);

  insert into public.auditoria (empresa_id, entidad, entidad_id, accion, usuario_id, detalle)
  values (v_empresa, 'pedido', p_pedido_id::text, 'REACTIVAR', auth.uid(),
          jsonb_build_object('desde', v_estado, 'motivo', p_motivo));

  return true;
end $$;

grant execute on function public.reactivar_pedido(uuid, text) to authenticated;

-- ---------- 8. Índices para consultas eficientes ----------
create index if not exists idx_pedidos_empresa_fecha
  on public.pedidos (empresa_id, fecha desc);
create index if not exists idx_pedidos_repartidor_estado
  on public.pedidos (repartidor_id, estado, fecha);
create index if not exists idx_pedidos_empresa_estado_fecha
  on public.pedidos (empresa_id, estado, fecha desc);
create index if not exists idx_detalle_pedido_pedido
  on public.detalle_pedido (pedido_id);
create index if not exists idx_pagos_pedido
  on public.pagos (pedido_id);
create index if not exists idx_pagos_empresa_fecha
  on public.pagos (empresa_id, fecha desc);
create index if not exists idx_pagos_cliente
  on public.pagos (cliente_id);
create index if not exists idx_movbal_empresa_cliente
  on public.movimiento_bal_on (empresa_id, cliente_id);
create index if not exists idx_movfierro_empresa_cliente
  on public.movimiento_fierro (empresa_id, cliente_id);
create index if not exists idx_auditoria_entidad
  on public.auditoria (entidad, entidad_id, fecha desc);
create index if not exists idx_clientes_empresa_telefono
  on public.clientes (empresa_id, telefono);

-- ---------- 9. Realtime para pedidos ----------
-- Para que el ADMIN vea los cambios del motorizado (y viceversa)
-- sin cerrar y abrir la app.
do $$
begin
  if not exists (
    select 1
      from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'pedidos'
  ) then
    alter publication supabase_realtime add table public.pedidos;
  end if;
end $$;

-- ---------- 10. Verificación (devuelve el estado de la migración) ----------
select 'migracion v3 aplicada' as resultado,
       (select count(*) from pg_indexes where schemaname = 'public' and indexname like 'idx_pedidos%') as indices_pedidos;
