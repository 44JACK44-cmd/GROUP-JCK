-- ============================================================
-- MIGRACIÓN v7 — Flujo operativo, cuaderno digital y rendición
-- (Agrupa v3 + v4 + v5 + v6, que nunca se aplicaron en la BD)
--
-- Se ejecuta como UN SOLO BLOQUE LÓGICO por secciones.
-- Es REEJECUTABLE y NO destructivo.
-- ============================================================

-- ---------- V3 · FLUJO OPERATIVO DE PEDIDOS ----------
do $$ begin
  if exists (select 1 from pg_constraint where conname = 'pedidos_forma_pago_check') then
    alter table public.pedidos drop constraint pedidos_forma_pago_check;
  end if;
end $$;
alter table public.pedidos
  add constraint pedidos_forma_pago_check
  check (forma_pago in ('EFECTIVO', 'YAPE', 'PLIN', 'TRANSFERENCIA', 'OTRO', 'DEUDA'));

do $$ begin
  if exists (select 1 from pg_constraint where conname = 'pedidos_estado_check') then
    alter table public.pedidos drop constraint pedidos_estado_check;
  end if;
end $$;
alter table public.pedidos
  add constraint pedidos_estado_check
  check (estado in ('NUEVO', 'ASIGNADO', 'EN_CAMINO', 'ENTREGADO', 'CANCELADO', 'NO_ENTREGADO'));

do $$ begin
  if exists (select 1 from pg_constraint where conname = 'entregas_estado_pago_check') then
    alter table public.entregas drop constraint entregas_estado_pago_check;
  end if;
end $$;
alter table public.entregas
  add constraint entregas_estado_pago_check
  check (estado_pago in ('PAGADO', 'PARCIAL', 'PENDIENTE'));

create or replace function public.trg_entrega_pedido_estado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.pedidos
     set estado = 'ENTREGADO'
   where id = new.pedido_id
     and empresa_id = new.empresa_id
     and estado in ('NUEVO', 'ASIGNADO', 'EN_CAMINO', 'NO_ENTREGADO');
  return new;
end $$;
drop trigger if exists trg_entrega_pedido_estado on public.entregas;
create trigger trg_entrega_pedido_estado
  after insert on public.entregas
  for each row execute function public.trg_entrega_pedido_estado();

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

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'pedidos'
  ) then
    alter publication supabase_realtime add table public.pedidos;
  end if;
end $$;

-- ---------- V4 · CUADERNO DIGITAL ----------
alter table public.pedidos
  add column if not exists origen text not null default 'ADMIN'
  check (origen in ('ADMIN', 'MOTORIZADO'));

create table if not exists public.incidencias (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas(id),
  usuario_id  uuid not null references auth.users(id),
  tipo        text not null
              check (tipo in ('FALLA', 'REPARACION', 'MANTENIMIENTO',
                              'ESTACIONAMIENTO', 'PEAJE', 'OTRO')),
  descripcion text not null,
  monto       numeric(10,2) not null default 0 check (monto >= 0),
  fecha       timestamptz not null default now(),
  uuid_offline text unique
);
alter table public.incidencias enable row level security;
drop policy if exists "incidencias_select" on public.incidencias;
create policy "incidencias_select" on public.incidencias
  for select to authenticated
  using (empresa_id = public.mi_empresa()
         and (public.es_admin() or usuario_id = auth.uid()));
drop policy if exists "incidencias_insert" on public.incidencias;
create policy "incidencias_insert" on public.incidencias
  for insert to authenticated
  with check (empresa_id = public.mi_empresa()
              and (public.es_admin() or usuario_id = auth.uid()));

-- ---------- V5 · RENDICIÓN Y CIERRE ----------
alter table public.gastos
  add column if not exists medio_pago text not null default 'EFECTIVO'
  check (medio_pago in ('EFECTIVO', 'YAPE', 'OTRO'));

create table if not exists public.rendiciones (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id),
  motorizado_id    uuid not null references auth.users(id),
  fecha            date not null default current_date,
  efectivo_declarado numeric(10,2) not null default 0,
  yape_declarado   numeric(10,2) not null default 0,
  observaciones     text,
  hora_entrega     timestamptz not null default now(),
  recibido_por     uuid references auth.users(id),
  estado           text not null default 'PENDIENTE'
                   check (estado in ('PENDIENTE', 'EN_REVISION', 'CON_DIFERENCIA',
                                     'OBSERVADA', 'APROBADA')),
  diferencia       numeric(10,2) not null default 0,
  justificacion    text,
  aprobado_por     uuid references auth.users(id),
  fecha_aprobacion timestamptz,
  uuid_offline     text unique,
  unique (empresa_id, motorizado_id, fecha)
);
alter table public.rendiciones enable row level security;
drop policy if exists "rendiciones_select" on public.rendiciones;
create policy "rendiciones_select" on public.rendiciones
  for select to authenticated
  using (empresa_id = public.mi_empresa()
         and (public.es_admin() or motorizado_id = auth.uid()));
drop policy if exists "rendiciones_insert" on public.rendiciones;
create policy "rendiciones_insert" on public.rendiciones
  for insert to authenticated
  with check (empresa_id = public.mi_empresa()
              and (public.es_admin() or motorizado_id = auth.uid()));
drop policy if exists "rendiciones_update" on public.rendiciones;
create policy "rendiciones_update" on public.rendiciones
  for update to authenticated
  using (empresa_id = public.mi_empresa()
         and (public.es_admin() or motorizado_id = auth.uid()))
  with check (empresa_id = public.mi_empresa()
               and (public.es_admin() or motorizado_id = auth.uid()));

create table if not exists public.cierre_diario (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id),
  fecha            date not null default current_date,
  total_ventas     numeric(10,2) not null default 0,
  efectivo_esperado numeric(10,2) not null default 0,
  efectivo_recibido numeric(10,2) not null default 0,
  yape_total       numeric(10,2) not null default 0,
  deudas_total     numeric(10,2) not null default 0,
  gastos_total     numeric(10,2) not null default 0,
  rendiciones_pendientes int not null default 0,
  diferencias      numeric(10,2) not null default 0,
  pedidos_pendientes int not null default 0,
  cerrado_por      uuid references auth.users(id),
  fecha_cierre     timestamptz,
  justificacion    text,
  estado           text not null default 'ABIERTO'
                   check (estado in ('ABIERTO', 'CERRADO')),
  unique (empresa_id, fecha)
);
alter table public.cierre_diario enable row level security;
drop policy if exists "cierre_select" on public.cierre_diario;
create policy "cierre_select" on public.cierre_diario
  for select to authenticated
  using (empresa_id = public.mi_empresa() and public.es_admin());
drop policy if exists "cierre_insert" on public.cierre_diario;
create policy "cierre_insert" on public.cierre_diario
  for insert to authenticated
  with check (empresa_id = public.mi_empresa() and public.es_admin());
drop policy if exists "cierre_update" on public.cierre_diario;
create policy "cierre_update" on public.cierre_diario
  for update to authenticated
  using (empresa_id = public.mi_empresa() and public.es_admin())
  with check (empresa_id = public.mi_empresa() and public.es_admin());

-- ---------- V6 · ZONAS Y ASIGNACIÓN ----------
alter table public.clientes
  add column if not exists zona text;

alter table public.perfiles
  add column if not exists zona text;

create or replace function public.asignar_por_zona(p_pedido_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
  v_zona text;
  v_motorizado uuid;
begin
  select p.empresa_id, c.zona into v_empresa, v_zona
    from public.pedidos p
    join public.clientes c on c.id = p.cliente_id
   where p.id = p_pedido_id;

  if v_empresa is null then
    return null;
  end if;

  select pr.id into v_motorizado
    from public.perfiles pr
   where pr.empresa_id = v_empresa
     and pr.rol = 'MOTORIZADO'
     and pr.activo = true
     and (v_zona is null or pr.zona = v_zona or pr.zona is null)
   order by (
     select count(*) from public.pedidos pp
      where pp.repartidor_id = pr.id
        and pp.estado in ('ASIGNADO', 'EN_CAMINO')
   ) asc
   limit 1;

  if v_motorizado is not null then
    update public.pedidos
       set repartidor_id = v_motorizado,
           estado = 'ASIGNADO'
     where id = p_pedido_id
       and estado = 'NUEVO';
  end if;

  return v_motorizado;
end $$;
grant execute on function public.asignar_por_zona(uuid) to authenticated;
